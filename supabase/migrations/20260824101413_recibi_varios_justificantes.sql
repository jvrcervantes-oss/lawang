-- destructivo-ok: no se borra ni una fila de datos. El unico DROP es el del trigger
-- trg_espejo_justificante que ESTA MISMA migracion crea tres lineas mas abajo (idempotencia
-- al reaplicar), y el unico DELETE va DENTRO del cuerpo de guardar_recibi, donde ya estaba
-- en la version viva: al reeditar un recibi rehace sus aplicaciones. Verificado contra
-- pg_get_functiondef antes de reescribirla; copia previa en Backups/ del proyecto.
-- Varios justificantes por recibí — 24-ago-2026. Documentación y porqués completos en
-- proyectos/Lawang/facturas/sql/recibi_varios_justificantes.sql
alter table public.facturas
  add column if not exists justificantes jsonb not null default '[]'::jsonb;

comment on column public.facturas.justificantes is
  'Justificantes de pago de un recibí: array de {path,nombre,subido_en}. FUENTE. justificante_path es su espejo (el primero), lo escribe trg_espejo_justificante.';

create or replace function public.espejo_justificante()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if jsonb_typeof(new.justificantes) = 'array' and jsonb_array_length(new.justificantes) > 0 then
    new.justificante_path := new.justificantes->0->>'path';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_espejo_justificante on public.facturas;
create trigger trg_espejo_justificante
  before insert or update on public.facturas
  for each row execute function public.espejo_justificante();

do $$
begin
  set local session_replication_role = replica;
  update public.facturas
     set justificantes = jsonb_build_array(jsonb_build_object('path', justificante_path))
   where justificante_path is not null
     and justificantes = '[]'::jsonb;
end;
$$;

create or replace function public.guardar_recibi(p_id uuid, p_factura jsonb, p_aplicaciones jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid;
  v_numero text;
  v_aplicacion jsonb;
  v_contrato_id uuid;
  v_justificantes jsonb;
  v_factura_id uuid;
  v_factura_numero text;
  v_factura_contrato uuid;
begin
  if not (public.es_agente() and public.puede('facturas')) then
    raise exception 'sin permiso para crear recibis' using errcode = '42501';
  end if;

  v_contrato_id := nullif(p_factura->>'contrato_id', '')::uuid;
  if v_contrato_id is null then
    raise exception 'el recibi necesita un contrato' using errcode = '23514';
  end if;

  v_justificantes := case when jsonb_typeof(p_factura->'justificantes') = 'array'
                          then p_factura->'justificantes' else '[]'::jsonb end;
  if jsonb_array_length(v_justificantes) = 0
     and nullif(p_factura->>'justificante_path', '') is not null then
    v_justificantes := jsonb_build_array(jsonb_build_object('path', p_factura->>'justificante_path'));
  end if;

  if jsonb_array_length(v_justificantes) = 0 then
    raise exception 'el recibi necesita un justificante de pago adjunto' using errcode = '23514';
  end if;
  if jsonb_array_length(v_justificantes) > 8 then
    raise exception 'demasiados justificantes en un recibi (maximo 8)' using errcode = '23514';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_justificantes) j
     where nullif(j->>'path', '') is null
        or not exists (select 1 from storage.objects o
                        where o.bucket_id = 'justificantes' and o.name = j->>'path')
  ) then
    raise exception 'algun justificante adjunto no existe en el almacenamiento' using errcode = '23514';
  end if;

  if jsonb_typeof(p_aplicaciones) <> 'array' or jsonb_array_length(p_aplicaciones) = 0 then
    raise exception 'el recibi necesita al menos una factura que salde' using errcode = '23514';
  end if;

  if p_id is null then
    insert into public.facturas
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
       total, moneda, fecha_emision, justificantes, datos)
    values
      ('recibi', p_factura->>'sociedad', p_factura->>'cliente_nombre', p_factura->>'proyecto_nombre',
       p_factura->>'contrato_numero', v_contrato_id, (p_factura->>'total')::numeric, p_factura->>'moneda',
       nullif(p_factura->>'fecha_emision','')::date, v_justificantes, p_factura->'datos')
    returning id, numero into v_id, v_numero;
  else
    update public.facturas set
      sociedad = p_factura->>'sociedad', cliente_nombre = p_factura->>'cliente_nombre',
      proyecto_nombre = p_factura->>'proyecto_nombre', contrato_numero = p_factura->>'contrato_numero',
      contrato_id = v_contrato_id, total = (p_factura->>'total')::numeric, moneda = p_factura->>'moneda',
      fecha_emision = nullif(p_factura->>'fecha_emision','')::date, justificantes = v_justificantes,
      datos = p_factura->'datos'
    where id = p_id and tipo = 'recibi' and anulada = false and public.es_suyo(creado_por)
    returning id, numero into v_id, v_numero;
    if v_id is null then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    delete from public.recibi_aplicaciones where recibi_id = v_id;
  end if;

  for v_aplicacion in select * from jsonb_array_elements(p_aplicaciones) loop
    v_factura_id := (v_aplicacion->>'factura_id')::uuid;

    select f.numero, f.contrato_id into v_factura_numero, v_factura_contrato
      from public.facturas f
     where f.id = v_factura_id
       and f.tipo = 'factura' and not coalesce(f.anulada, false);
    if not found then
      raise exception 'la aplicacion referencia una factura invalida o anulada' using errcode = '23514';
    end if;

    if v_factura_contrato is null then
      if public.es_super_admin() then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_factura_huerfana',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero));
      else
        raise exception 'la factura % no cuelga de ningun contrato: no se le puede aplicar un cobro (LAW-38)',
          coalesce(v_factura_numero, '?') using errcode = '23514';
      end if;
    elsif not public.contratos_mismo_comprador(v_contrato_id, v_factura_contrato) then
      if public.es_super_admin() then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_otro_comprador',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero,
                             'importe', v_aplicacion->>'importe'));
      else
        raise exception 'la factura % es de otro comprador que el recibi', coalesce(v_factura_numero, '?')
          using errcode = '23514';
      end if;
    end if;

    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, v_factura_id, (v_aplicacion->>'importe')::numeric, (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$function$;

revoke all on function public.guardar_recibi(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.guardar_recibi(uuid, jsonb, jsonb) to authenticated;;
