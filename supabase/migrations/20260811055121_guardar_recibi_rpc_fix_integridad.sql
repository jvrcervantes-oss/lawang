-- destructivo-ok: el DELETE de aqui abajo va acotado a `where recibi_id = v_id`,
-- un solo recibi identificado por PK -- patron borrar-y-reinsertar del reparto
-- de aplicaciones de ESE recibi al editarlo, no un borrado masivo (mismo
-- comentario que ya paso este mismo gate en la migracion anterior de esta
-- misma funcion).
--
-- Fix de dos hallazgos reales de Seguridad/Administracion sobre guardar_recibi_rpc
-- (11-ago-2026), confirmados en produccion antes de este fix:
--
-- ALTA: SECURITY DEFINER salta la RLS de recibi_aplicaciones que exigia
-- f.tipo='factura' y f.anulada=false del lado factura -- sin repetir ese check
-- aqui dentro, la funcion "bendecida" quedaba MENOS estricta que el insert
-- directo que reemplaza: se podia saldar un recibi contra una factura anulada,
-- o contra el id de OTRO RECIBI (el FK solo exige que exista una fila en
-- facturas, no el tipo). Ahora se valida por cada aplicacion antes de insertar.
--
-- MEDIA: "justificante_path no nulo" no comprobaba que el objeto existiera de
-- verdad en el bucket privado `justificantes` -- cualquier string pasaba el
-- gate. Ahora se exige que exista la fila en storage.objects.

create or replace function public.guardar_recibi(p_id uuid, p_factura jsonb, p_aplicaciones jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_numero text;
  v_aplicacion jsonb;
  v_contrato_id uuid;
  v_justificante text;
begin
  if not (public.es_agente() and public.puede('facturas')) then
    raise exception 'sin permiso para crear recibis' using errcode = '42501';
  end if;

  v_contrato_id := nullif(p_factura->>'contrato_id', '')::uuid;
  v_justificante := nullif(p_factura->>'justificante_path', '');
  if v_contrato_id is null then
    raise exception 'el recibi necesita un contrato' using errcode = '23514';
  end if;
  if v_justificante is null then
    raise exception 'el recibi necesita un justificante de pago adjunto' using errcode = '23514';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'justificantes' and name = v_justificante) then
    raise exception 'el justificante adjunto no existe en el almacenamiento' using errcode = '23514';
  end if;
  if jsonb_typeof(p_aplicaciones) <> 'array' or jsonb_array_length(p_aplicaciones) = 0 then
    raise exception 'el recibi necesita al menos una factura que salde' using errcode = '23514';
  end if;

  if p_id is null then
    insert into public.facturas
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
       total, moneda, fecha_emision, justificante_path, datos)
    values
      ('recibi', p_factura->>'sociedad', p_factura->>'cliente_nombre', p_factura->>'proyecto_nombre',
       p_factura->>'contrato_numero', v_contrato_id, (p_factura->>'total')::numeric, p_factura->>'moneda',
       nullif(p_factura->>'fecha_emision','')::date, v_justificante, p_factura->'datos')
    returning id, numero into v_id, v_numero;
  else
    update public.facturas set
      sociedad = p_factura->>'sociedad', cliente_nombre = p_factura->>'cliente_nombre',
      proyecto_nombre = p_factura->>'proyecto_nombre', contrato_numero = p_factura->>'contrato_numero',
      contrato_id = v_contrato_id, total = (p_factura->>'total')::numeric, moneda = p_factura->>'moneda',
      fecha_emision = nullif(p_factura->>'fecha_emision','')::date, justificante_path = v_justificante,
      datos = p_factura->'datos'
    where id = p_id and tipo = 'recibi' and anulada = false and public.es_suyo(creado_por)
    returning id, numero into v_id, v_numero;
    if v_id is null then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    delete from public.recibi_aplicaciones where recibi_id = v_id;
  end if;

  for v_aplicacion in select * from jsonb_array_elements(p_aplicaciones) loop
    if not exists (
      select 1 from public.facturas f
       where f.id = (v_aplicacion->>'factura_id')::uuid
         and f.tipo = 'factura' and not coalesce(f.anulada, false)
    ) then
      raise exception 'la aplicacion referencia una factura invalida o anulada' using errcode = '23514';
    end if;
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, (v_aplicacion->>'factura_id')::uuid, (v_aplicacion->>'importe')::numeric,
            (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$$;
;
