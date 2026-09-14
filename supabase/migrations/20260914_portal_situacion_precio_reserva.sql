-- portal_situacion(): anade `precio_reserva` a cada contrato del area de clientes.
--
-- POR QUE. El area de clientes ensenaba el doble de lo que el comprador debe:
-- sumaba la Carta de Reserva junto al Bloqueo de Parcela y la Construccion que
-- la sustituyen, y esos tres documentos describen UNA villa, no tres. La regla
-- vive en contracts/assets/vocabulario.js (`lwEsPreliminar`); la suite la
-- aprendio el 12-ago-2026 en compradores/ y el 14-ago en operaciones/, y el
-- portal -- la unica pantalla que ve el CLIENTE -- nunca la aplico.
--
-- Al dejar de sumar la Carta aparece el caso contrario: un comprador que SOLO
-- tiene Carta, aun sin contrato definitivo, se quedaria con el resumen en
-- blanco, y eso se lee como <<no debes nada>>. Lo que debe de verdad es la
-- CUOTA de reserva, exigible a los 5 dias habiles de la firma y con retencion
-- si el reservante desiste (carta_reserva_hak_sewa, cl. 4.1/7.2 -- hallazgo
-- Legal ALTA del 12-ago-2026). Ese importe vive en
-- `datos->'fields'->>'precio_reserva'` y hasta hoy no viajaba al portal.
--
-- No anade coste: `c.datos` ya se descomprimia aqui para `precio_total` y los
-- hitos, asi que no hay un TOAST nuevo que pagar.
--
-- Se reescribe la funcion ENTERA a proposito (CREATE OR REPLACE no admite
-- parches): SECURITY DEFINER y `SET search_path TO ''` se conservan tal cual --
-- perderlos aqui abriria el portal de par en par.
CREATE OR REPLACE FUNCTION public.portal_situacion()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  r jsonb;
begin
  if not public.es_portal() or v_email = '' then
    raise exception 'solo usuarios del portal' using errcode = '42501';
  end if;

  with mis_clientes as (
    select distinct pa.client_id
      from public.portal_accesos pa
     where pa.activo and pa.email = v_email
  ),
  mis_ids as (
    select distinct cc.contrato_id as id
      from public.contrato_compradores cc
      join mis_clientes mc on mc.client_id = cc.client_id
  )
  select jsonb_build_object(
    'nombre', (select cl.full_name from public.clients cl
                join mis_clientes mc on mc.client_id = cl.id
                order by cl.created_at limit 1),
    'email', (select cl.email from public.clients cl
                join mis_clientes mc on mc.client_id = cl.id
                order by cl.created_at limit 1),
    'telefono', (select cl.phone from public.clients cl
                join mis_clientes mc on mc.client_id = cl.id
                order by cl.created_at limit 1),
    'pais', (select cl.nationality from public.clients cl
                join mis_clientes mc on mc.client_id = cl.id
                order by cl.created_at limit 1),
    'client_id', (select mc.client_id from mis_clientes mc
                    join public.clients cl on cl.id = mc.client_id
                   order by cl.created_at limit 1),
    'contratos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',          c.id,
        'numero',      c.numero,
        'tipo',        c.tipo,
        'proyecto',    c.proyecto_nombre,
        'parcela',     c.datos->'fields'->>'parcela_codigo',
        'precio',      c.precio_total,
        'precio_txt',  nullif(c.datos->'fields'->>'precio_total', ''),
        -- la cuota de reserva: el unico importe exigible mientras no haya
        -- contrato definitivo (ver la cabecera de esta migracion)
        'precio_reserva', nullif(c.datos->'fields'->>'precio_reserva', ''),
        'moneda',      c.moneda,
        'fecha_firma', c.fecha_firma,
        'firmado',     coalesce(c.bloqueado, false),
        'pdf',         c.pdf_firmado_path,
        'hitos',       case when jsonb_typeof(c.datos->'hitos') = 'array'
                            then c.datos->'hitos' else '[]'::jsonb end,
        'cobrado',     coalesce(public.contrato_cobrado(c.id), 0)
      ) order by c.created_at)
      from public.contratos c
      join mis_ids m on m.id = c.id), '[]'::jsonb),
    'firma_pendiente', coalesce((
      select jsonb_agg(jsonb_build_object(
        'contrato_id',  cf.contrato_id,
        'enviado_en',   cf.creado_en,
        'expira_en',    cf.expira_en,
        'enlace',       cf.enlace_firma
      ) order by cf.creado_en desc)
      from public.contrato_firmas cf
      join mis_ids m on m.id = cf.contrato_id
     where cf.estado = 'pendiente'
       and cf.expira_en > now()
       and cf.enlace_firma is not null
       and lower(btrim(cf.firmante_email)) = v_email), '[]'::jsonb),
    'facturas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',              f.id,
        'numero',          f.numero,
        'tipo',            f.tipo,
        'sociedad',        f.sociedad,
        'contrato_numero', f.contrato_numero,
        'fecha',           f.fecha_emision,
        'total',           f.total,
        'moneda',          f.moneda,
        'cliente',         coalesce(public.contrato_nombres_factura(cf.datos), f.cliente_nombre),
        'proyecto',        f.proyecto_nombre,
        'lineas',          f.datos->'lineas',
        'totales',         f.datos->'totales',
        'fields',          f.datos->'fields'
      ) order by f.fecha_emision desc, f.numero desc)
      from public.facturas f
      join public.contratos cf on cf.id = f.contrato_id
     where f.contrato_id in (select id from mis_ids)
       and not coalesce(f.anulada, false)
       and (f.tipo <> 'proforma' or f.enviada)), '[]'::jsonb),
    'obra', coalesce((
      select jsonb_agg(jsonb_build_object(
        'unidad',          u.codigo,
        'proyecto',        u.proyecto,
        'contrato_numero', c2.numero,
        'fase',            u.obra_fase,
        'fecha_entrega',   u.obra_fecha_entrega,
        'actualizado',     u.obra_actualizado,
        'fotos', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'path', o.path, 'titulo', o.titulo, 'fecha', o.tomada_en)
                 order by o.tomada_en desc, o.creado_en desc)
            from public.obra_fotos o
           where o.unidad_id = u.id and o.visible), '[]'::jsonb)
      ))
      from public.unidades u
      join public.contratos c2 on c2.id = u.contrato_id
      join mis_ids m on m.id = c2.id), '[]'::jsonb),
    'documentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',          dp.id,
        'titulo',      dp.titulo,
        'descripcion', dp.descripcion,
        'categoria',   dp.categoria,
        'proyecto',    dp.proyecto,
        'url',         dp.url,
        'path',        dp.path
      ) order by dp.creado_en desc)
      from public.documentos_proyecto dp
     where dp.visible_portal
       and exists (
         select 1 from public.contratos c3
         join mis_ids m3 on m3.id = c3.id
        where public.mismo_proyecto(dp.proyecto, c3.proyecto_nombre)
       )), '[]'::jsonb),
    'kyc', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tipo',   doc.doc_type,
        'subido', doc.uploaded_at,
        'caduca', doc.caduca_el,
        'path',   doc.storage_path
      ) order by doc.uploaded_at desc)
      from public.documents doc
      join mis_clientes mc2 on mc2.client_id = doc.client_id), '[]'::jsonb),
    'fases', coalesce((
      select jsonb_agg(jsonb_build_object(
               'orden', ff.orden, 'clave', ff.clave, 'es', ff.es, 'en', ff.en)
             order by ff.orden)
        from public.obra_fases ff), '[]'::jsonb),
    'tickets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',            hs.id,
        'categoria',     hs.categoria,
        'estado',        hs.estado,
        'actualizado_en', hs.actualizado_en,
        'mensajes', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'id', mm.id, 'de', mm.de, 'autor', mm.autor, 'texto', mm.texto, 'creado_en', mm.creado_en)
                 order by mm.creado_en)
            from public.mensajes_comprador mm
           where mm.hilo_id = hs.id), '[]'::jsonb)
      ) order by hs.actualizado_en desc)
      from public.hilo_soporte hs
      join mis_clientes mc7 on mc7.client_id = hs.client_id), '[]'::jsonb),
    'prefs', coalesce((
      select jsonb_build_object('pref_email', pc.pref_email, 'pref_sms', pc.pref_sms,
                                 'notif_visto_hasta', pc.notif_visto_hasta)
        from public.preferencias_comprador pc
        join mis_clientes mc5 on mc5.client_id = pc.client_id
       order by pc.actualizado_en desc limit 1),
      jsonb_build_object('pref_email', true, 'pref_sms', false, 'notif_visto_hasta', null))
  ) into r;
  return r;
end
$function$;
