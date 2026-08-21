-- destructivo-ok: el DELETE de aqui abajo va acotado a `where recibi_id = v_id`,
-- un solo recibi identificado por PK -- es el patron borrar-y-reinsertar para
-- sustituir el reparto de aplicaciones de ESE recibi al editarlo, no un borrado
-- masivo. Falso positivo del heuristico de no_destruir.py sobre DELETE dentro
-- de una funcion plpgsql (misma clase que CREATE TRIGGER ... BEFORE UPDATE).
--
-- Blindaje a nivel de base de datos de "recibi exige factura y justificante,
-- no es opcional" (11-ago-2026, peticion del owner) -- hasta ahora esa regla
-- solo vivia en el JS de facturas/index.html, saltable por un INSERT directo
-- a la API REST (el mismo tipo de hueco que Seguridad ya habia cazado para
-- los topes de recibi_aplicaciones).
--
-- 1) justificante_path NOT NULL para tipo='recibi', NOT VALID (no rompe
--    filas viejas, si exige el dato en cualquier INSERT/UPDATE nuevo).
-- 2) La regla "al menos una factura que salda" es cruzada entre tablas (la
--    fila del recibi en `facturas` + N filas en `recibi_aplicaciones`) y NO
--    se puede expresar como CHECK -- un CHECK es por fila, no puede saber si
--    OTRA tabla tiene filas relacionadas. La solucion es que las dos
--    inserciones dejen de ser dos peticiones REST sueltas (lo que hacia
--    facturas/index.html) y pasen a ser una sola funcion atomica: si
--    p_aplicaciones llega vacio, la funcion entera falla y no se crea NADA,
--    ni el recibi ni sus aplicaciones -- no puede quedar un recibi huerfano.

alter table public.facturas
  add constraint facturas_recibi_justificante_obligatorio
  check (tipo <> 'recibi' or justificante_path is not null)
  not valid;

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
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, (v_aplicacion->>'factura_id')::uuid, (v_aplicacion->>'importe')::numeric,
            (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$$;

revoke all on function public.guardar_recibi(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.guardar_recibi(uuid, jsonb, jsonb) to authenticated;
;
