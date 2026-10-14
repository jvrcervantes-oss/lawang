-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68). El maestro tiene su propio guardar_recibi (sin la columna
--   historico_sin_justificante, que es solo de Lawang, LAW-40); llevar A1-A4 y C3 al maestro va en su fila de pendientes (AXW-333).
-- GUARDAR_RECIBI: EL TOTAL ES LA SUMA DE LO QUE SE APLICA, SE VALIDA TODO ANTES DE NUMERAR, SIN IMPUESTO, «OTROS» SOLO ADMIN Y EL
--   HISTORICO SIN JUSTIFICANTE SE PUEDE APLICAR (14-oct-2026, Backend). Bloque A + C3-recibis del plan «arreglos seguros y reversibles
--   de Contratos y Facturas» (revision previa de Backend #337 y de Seguridad #338, plan cerrado) + fallo 1 de los que encontro el
--   orquestador al aplicar REC00015 (decision del owner del 14-oct, opcion A: dinero real).
-- QUE HACE (y por que):
--   Orden de permisos primero (Seguridad #338): herramienta -> contrato que ves -> alcance restringido (como hoy) -> si se EDITA, se
--     bloquea la fila vieja con su filtro de autoria (y «ya se envio») ANTES de cualquier otra validacion o mensaje.
--   Fallo 1 · JUSTIFICANTE: un recibi marcado historico_sin_justificante (LAW-40, recibis de antes del 11-ago sin justificante; la
--     marca solo la pone una migracion, trg_facturas_historico_solo_migracion) se puede volver a guardar sin justificante. La exencion
--     sale SOLO de la fila guardada y bloqueada (v_viejo), nunca del payload ni de una fecha (que llega de la pantalla y se puede
--     fabricar). Un recibi nuevo sigue exigiendo justificante. Medido el 14-oct: 12 recibis vivos con la marca y sin justificante.
--   A1 · NUMERACION: TODAS las aplicaciones se validan antes del insert, para que un rechazo no gaste numero. Reduce los huecos, no
--     los evita (nextval se gasta igual si falla algo despues). registra_privilegio va despues de escribir (necesita el numero).
--     Al editar, el pendiente de cada factura excluye las aplicaciones del propio recibi (antes se validaba despues de borrarlas).
--     Una factura repetida en las aplicaciones se rechaza.
--   VISIBILIDAD: el mensaje «no es un documento que veas» ya no da el NUMERO de la factura (lo daba a quien no la ve: oraculo).
--   A2 · IMPORTES: el total y cada aplicacion se leen con ::numeric si llegan como numero JSON (lo que manda la pantalla) y con
--     lw_parse_importe si llegan como texto (con «120.000», ::numeric daba 120). Se redondean a los decimales de la moneda.
--   A4 · TOTAL: el servidor CALCULA el total como la suma de las aplicaciones y rechaza el recibi si el de la pantalla no casa. Sin
--     salto para nadie. Antes un recibi podia decir 100.000 aplicando 1, y _contrato_cobrado_interno contaba los 99.999 de mas como
--     cobrado (movia la parcela a «vendida» y las comisiones). _contrato_cobrado_interno NO se toca (F2 y comisiones).
--   A3 · IMPUESTO: un recibi no lleva impuesto (el total guardado no lo sumaba y el papel si): se quitan imp_pct e imp_etiqueta de
--     datos.fields. Medido el 14-oct: 0 recibis con impuesto. La pantalla quita su campo (editores.js).
--   C3 · CUENTA «OTROS» (titular y numero escritos a mano, que salen en el papel sin comprobar): solo la usa un admin de la empresa
--     del contrato. Un no admin no puede elegir «otros»; en un recibi que YA la lleva (7 de los 13 documentos con «otros» son
--     recibis) solo puede guardar si la cuenta y todos sus banco_* quedan exactamente igual. Con otra cuenta, sus banco_* se descartan
--     (el papel solo los imprime con «otros», documento.js:64).
-- LO QUE NO HACE: no toca datos (REC00015 lo aplica el orquestador por la pantalla, con el OK del owner). Si el owner aplica
--   REC00015 a INV00212 (39.220 = 39.220) entra la aplicacion entera o nada: todo va en la misma transaccion.
-- Se REESCRIBE ENTERA desde su definicion viva (7,4 KB), md5 de pg_get_functiondef sin retorno de carro medido el 14-oct-2026 en la
--   sesion 1014-2159 (solo lectura): guardar_recibi(uuid,jsonb,jsonb) 43a4c655711c0ef218b670ebe01c1585. Si ya no tiene ese md5 ni
--   lleva este arreglo, el bloque $antes$ lanza y no se aplica NADA. Idempotente. create or replace conserva dueno y permisos
--   (authenticated si, anon no, service_role si, medido el 14-oct); el bloque $cierre$ lo comprueba.
-- REVERTIR: supabase/reversion_recibi_total_suma_y_exento/REVERSION.sql (el texto vivo de antes, tal cual).
-- Prueba: supabase/pruebas/recibi_total_suma_y_exento.sql (crea contratos y documentos: SOLO en rama):
--   python erp/rama_prueba.py lawang --lawang <copia> --aplica 20261014223000_recibi_total_suma_y_exento.sql
--          --prueba recibi_total_suma_y_exento.sql

set local lock_timeout = '5s';

do $antes$
begin
  if md5(replace(pg_get_functiondef('public.guardar_recibi(uuid,jsonb,jsonb)'::regprocedure), chr(13), '')) <> '43a4c655711c0ef218b670ebe01c1585'
     and position('v_exento' in pg_get_functiondef('public.guardar_recibi(uuid,jsonb,jsonb)'::regprocedure)) = 0 then
    raise exception 'recibi_total_suma_y_exento: guardar_recibi no es la definicion viva leida el 14-oct (md5 distinto) ni lleva ya el arreglo; no se aplica nada';
  end if;
end $antes$;

CREATE OR REPLACE FUNCTION public.guardar_recibi(p_id uuid, p_factura jsonb, p_aplicaciones jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_numero text;
  v_aplicacion jsonb;
  v_contrato_id uuid;
  v_justificantes jsonb;
  v_factura_id uuid;
  v_factura_numero text;
  v_factura_contrato uuid;
  v_factura_autor text;
  v_factura_proyecto uuid;
  v_importe_aplic numeric;
  v_pend_factura numeric;
  v_moneda_factura text;
  v_rest boolean := public.alcance_restringido() and not public.es_admin();
  v_pnombre text := p_factura->>'proyecto_nombre';
  v_pid uuid; v_emp text; v_emp_fac text;
  v_viejo public.facturas%rowtype;
  -- 14-oct-2026 (bloque A + C3 + fallo 1)
  v_exento boolean := false;
  v_dec int := public.lw_decimales(p_factura->>'moneda');
  v_total numeric := 0;
  v_total_pantalla numeric;
  v_apl jsonb := '[]'::jsonb;
  v_priv jsonb := '[]'::jsonb;
  v_p jsonb;
  v_datos jsonb := p_factura->'datos';
  v_campos jsonb;
  v_admin boolean;
  c_banco constant text[] := array['banco_titular', 'banco_nombre', 'banco_cuenta', 'banco_codigo', 'banco_direccion', 'banco_extra'];
begin
  if not public._puede_herr('facturas') then
    raise exception 'sin permiso para crear recibis' using errcode = '42501';
  end if;

  v_contrato_id := nullif(p_factura->>'contrato_id', '')::uuid;
  if v_contrato_id is null then
    raise exception 'el recibi necesita un contrato' using errcode = '23514';
  end if;

  if not public.es_super_admin_de(public._empresa_doc(null::uuid, v_contrato_id))
     and not exists (select 1 from public.contratos c
                      where c.id = v_contrato_id and public.puede_ver_contrato(c.id)) then
    raise exception 'No puedes emitir un recibí sobre un contrato que no ves' using errcode = '42501';
  end if;

  v_emp := public._empresa_doc(null::uuid, v_contrato_id);
  if v_rest then
    select c.proyecto_id into v_pid from public.contratos c where c.id = v_contrato_id;
    select pr.nombre into v_pnombre from public.proyectos pr where pr.id = v_pid;
    if v_emp is null or not public.puede_empresa(v_emp) then
      raise exception 'Ese recibí no es de ninguna de tus empresas' using errcode = '42501';
    end if;
    if (p_id is null or (p_factura->>'sociedad') is distinct from (select f.sociedad from public.facturas f where f.id = p_id))
       and not exists (select 1 from public.empresas e where e.clave = v_emp and e.sociedad_clave = p_factura->>'sociedad') then
      raise exception 'Ese recibí tiene que salir por la sociedad de la empresa del proyecto' using errcode = '42501';
    end if;
  end if;

  -- Editar: la fila vieja se bloquea con el MISMO filtro de autoria que el UPDATE de abajo, ANTES de cualquier otra validacion
  -- (14-oct-2026, Seguridad #338: los permisos van primero). LAW-37: un recibi enviado no se edita.
  if p_id is not null then
    select * into v_viejo from public.facturas f
     where f.id = p_id and f.tipo = 'recibi' and f.anulada = false
       and (public.es_suyo(f.creado_por) or public.es_admin_de(public._empresa_doc(f.proyecto_id, f.contrato_id)))
     for update;
    if not found then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    if coalesce(v_viejo.enviada, false) then
      raise exception 'El recibí % ya se envió al cliente: no se edita. Anúlalo y emite otro si hace falta corregirlo.',
        coalesce(v_viejo.numero, '?') using errcode = '23514';
    end if;
    -- LAW-40 (fallo 1, 14-oct-2026): la exencion de justificante sale SOLO de la marca de la fila guardada
    v_exento := coalesce(v_viejo.historico_sin_justificante, false);
  end if;

  v_justificantes := case when jsonb_typeof(p_factura->'justificantes') = 'array'
                          then p_factura->'justificantes' else '[]'::jsonb end;
  if jsonb_array_length(v_justificantes) = 0
     and nullif(p_factura->>'justificante_path', '') is not null then
    v_justificantes := jsonb_build_array(jsonb_build_object('path', p_factura->>'justificante_path'));
  end if;

  if jsonb_array_length(v_justificantes) = 0 and not v_exento then
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
  if (select count(*) from jsonb_array_elements(p_aplicaciones) a)
     <> (select count(distinct a->>'factura_id') from jsonb_array_elements(p_aplicaciones) a) then
    raise exception 'la misma factura aparece dos veces en el recibi: junta sus importes en una sola linea' using errcode = '23514';
  end if;

  -- A1 (14-oct-2026): TODAS las aplicaciones se validan ANTES de escribir, para que un rechazo no gaste numero
  perform 1 from public.facturas fl
   where fl.id in (select (a->>'factura_id')::uuid from jsonb_array_elements(p_aplicaciones) a)
   order by fl.id for update;
  for v_aplicacion in select * from jsonb_array_elements(p_aplicaciones) loop
    v_factura_id := (v_aplicacion->>'factura_id')::uuid;

    select f.numero, f.contrato_id, f.creado_por, f.proyecto_id
      into v_factura_numero, v_factura_contrato, v_factura_autor, v_factura_proyecto
      from public.facturas f
     where f.id = v_factura_id
       and f.tipo = 'factura' and not coalesce(f.anulada, false);
    if not found then
      raise exception 'la aplicacion referencia una factura invalida o anulada' using errcode = '23514';
    end if;
    v_emp_fac := public._empresa_doc(v_factura_proyecto, v_factura_contrato);

    -- sin numero: quien no ve la factura no se entera de cual es (14-oct-2026, Seguridad #338)
    if not public.es_super_admin_de(v_emp_fac)
       and not public.documento_visible(v_factura_autor, v_factura_proyecto, v_factura_contrato) then
      raise exception 'una de las facturas no es un documento que veas: no le puedes aplicar un cobro' using errcode = '42501';
    end if;

    if v_factura_contrato is null then
      if public.es_super_admin_de(v_emp_fac) then
        v_priv := v_priv || jsonb_build_array(jsonb_build_object('evento', 'cobro_a_factura_huerfana', 'factura', v_factura_numero));
      else
        raise exception 'la factura % no cuelga de ningun contrato: no se le puede aplicar un cobro (LAW-38)',
          coalesce(v_factura_numero, '?') using errcode = '23514';
      end if;
    elsif not public.contratos_mismo_comprador(v_contrato_id, v_factura_contrato) then
      if public.es_super_admin_de(v_emp) and public.es_super_admin_de(v_emp_fac) then
        v_priv := v_priv || jsonb_build_array(jsonb_build_object('evento', 'cobro_a_otro_comprador', 'factura', v_factura_numero,
                                                                 'importe', v_aplicacion->>'importe'));
      else
        raise exception 'la factura % es de otro comprador que el recibi', coalesce(v_factura_numero, '?')
          using errcode = '23514';
      end if;
    end if;

    -- A2: numero JSON tal cual; texto por el parser de importes («120.000» = 120000, no 120)
    v_importe_aplic := case jsonb_typeof(v_aplicacion->'importe')
                         when 'number' then (v_aplicacion->>'importe')::numeric
                         when 'string' then public.lw_parse_importe(v_aplicacion->>'importe')
                       end;
    v_importe_aplic := round(v_importe_aplic, v_dec);
    if v_importe_aplic is null or v_importe_aplic <= 0 then
      raise exception 'el importe que se aplica a la factura % tiene que ser mayor que cero', coalesce(v_factura_numero, '?') using errcode = '23514';
    end if;
    -- al editar, lo ya aplicado por ESTE recibi no cuenta como cobrado de antes
    select f.total - coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                                 join public.facturas rc on rc.id = ra.recibi_id
                                where ra.factura_id = f.id and not coalesce(rc.anulada, false)
                                  and ra.recibi_id is distinct from p_id), 0), f.moneda
      into v_pend_factura, v_moneda_factura from public.facturas f where f.id = v_factura_id;
    if v_importe_aplic > v_pend_factura + power(10::numeric, -public.lw_decimales(v_moneda_factura)) then
      raise exception 'la factura % solo tiene % pendiente de cobro y este recibí le aplica %', coalesce(v_factura_numero, '?'), v_pend_factura, v_importe_aplic using errcode = '23514';
    end if;
    v_total := v_total + v_importe_aplic;
    v_apl := v_apl || jsonb_build_array(jsonb_build_object('factura_id', v_factura_id, 'importe', v_importe_aplic));
  end loop;

  -- A4 (14-oct-2026): el total del recibi es la suma de lo que aplica; el de la pantalla solo se compara
  v_total_pantalla := case jsonb_typeof(p_factura->'total')
                        when 'number' then (p_factura->>'total')::numeric
                        when 'string' then public.lw_parse_importe(p_factura->>'total')
                      end;
  if v_total_pantalla is null or round(v_total_pantalla, v_dec) <> v_total then
    raise exception 'el total del recibí (%) no es la suma de lo que aplica a sus facturas (%): un recibí solo cobra lo que salda',
      coalesce(v_total_pantalla::text, 'vacío'), v_total using errcode = '23514';
  end if;

  -- A3 (sin impuesto) y C3 (cuenta «otros» solo admin de la empresa), sobre datos.fields
  if jsonb_typeof(v_datos) = 'object' and jsonb_typeof(v_datos->'fields') = 'object' then
    v_campos := (v_datos->'fields') - 'imp_pct' - 'imp_etiqueta';
    v_admin := public.es_admin_de(v_emp);
    if not v_admin then
      if v_campos->>'cuenta' = 'otros' then
        if p_id is null
           or (v_viejo.datos->'fields'->>'cuenta') is distinct from 'otros'
           or exists (select 1 from unnest(c_banco) k
                       where (v_campos->>k) is distinct from (v_viejo.datos->'fields'->>k)) then
          raise exception 'La cuenta «Otros» (escrita a mano) solo la puede usar un administrador de la empresa: elige una cuenta de la lista.'
            using errcode = '42501';
        end if;
      else
        v_campos := v_campos - c_banco;
      end if;
    end if;
    v_datos := jsonb_set(v_datos, '{fields}', v_campos);
  end if;

  if p_id is null then
    insert into public.facturas
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
       total, moneda, fecha_emision, justificantes, datos)
    values
      ('recibi', p_factura->>'sociedad', p_factura->>'cliente_nombre', v_pnombre,
       p_factura->>'contrato_numero', v_contrato_id, v_total, p_factura->>'moneda',
       nullif(p_factura->>'fecha_emision','')::date, v_justificantes, v_datos)
    returning id, numero into v_id, v_numero;
  else
    update public.facturas set
      sociedad = p_factura->>'sociedad', cliente_nombre = p_factura->>'cliente_nombre',
      proyecto_nombre = v_pnombre, contrato_numero = p_factura->>'contrato_numero',
      contrato_id = v_contrato_id, total = v_total, moneda = p_factura->>'moneda',
      fecha_emision = nullif(p_factura->>'fecha_emision','')::date, justificantes = v_justificantes,
      datos = v_datos
    where id = p_id and tipo = 'recibi' and anulada = false
      and (public.es_suyo(creado_por) or public.es_admin_de(public._empresa_doc(proyecto_id, contrato_id)))
    returning id, numero into v_id, v_numero;
    if v_id is null then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    delete from public.recibi_aplicaciones where recibi_id = v_id;
  end if;

  for v_p in select * from jsonb_array_elements(v_priv) loop
    perform public.registra_privilegio(v_contrato_id, v_p->>'evento',
      (v_p - 'evento') || jsonb_build_object('recibi', v_numero));
  end loop;

  for v_aplicacion in select * from jsonb_array_elements(v_apl) loop
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, (v_aplicacion->>'factura_id')::uuid, (v_aplicacion->>'importe')::numeric, (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$function$;

do $cierre$
begin
  if not has_function_privilege('authenticated', 'public.guardar_recibi(uuid,jsonb,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.guardar_recibi(uuid,jsonb,jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.guardar_recibi(uuid,jsonb,jsonb)', 'execute') then
    raise exception 'recibi_total_suma_y_exento: los permisos de guardar_recibi cambiaron; no se aplica';
  end if;
end $cierre$;
