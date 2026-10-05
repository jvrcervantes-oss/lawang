-- Facturas: tope por cadena de contratos + tope del recibí contra el pendiente + saldo del contrato (5-oct-2026, owner).
-- Revisión previa #206 (Administración + Datos). Qué cierra, y por qué en el servidor (el navegador no se cree):
--   1. factura_guarda aceptaba cualquier total: solo comprobaba que las líneas sumaran lo que decía la pantalla.
--   2. guardar_recibi aceptaba cualquier importe por factura: el tope «no más que el pendiente» vivía solo en la pantalla.
--
-- TOPE DE FACTURA — por CADENA, no por contrato suelto (medido en producción el 5-oct: por contrato suelto 39 de 122
-- salían «excedidos», porque la factura de construcción incluye el pago del suelo del Bloqueo padre; por cadena, 3 de 103).
--   · Cadena = raíz (coalesce(contrato_padre_id, id)) + sus hijos. Precio de la cadena = suma de precio_total de los
--     contratos NO preliminares (tipo like 'carta_reserva%' no suma, igual que cuentaGrupo() de operaciones-cuentas.js).
--   · Facturado = facturas tipo 'factura' vivas de la cadena en la moneda de la raíz, SIN impuesto (datos.totales.subtotal).
--   · No se aplica si algún contrato sumable no tiene precio_total (12 hoy: sin precio no hay con qué comparar), ni a
--     proformas, ni a otra moneda.
--   · No-regresión: en una edición solo bloquea si el subtotal SUBE respecto al guardado; las 3 cadenas ya excedidas
--     (RP00106, RP00079, RP00082) siguen editables sin subir.
--   · super_admin puede pasarse el tope y queda en contrato_eventos ('factura_sobre_tope'), igual que los demás
--     privilegios de esa función. Un agente no.
--   · Tolerancia = una unidad del último decimal de la moneda (0,01 EUR · 1 IDR).
--   · Concurrencia: pg_advisory_xact_lock sobre la raíz serializa dos altas simultáneas de la misma cadena.
-- TOPE DE RECIBÍ: cada aplicación ≤ pendiente de su factura (total − recibís no anulados aplicados). Las facturas se
--   bloquean TODAS a la vez y por id ordenado antes del bucle (dos recibís cruzados no se interbloquean).
--
-- SALDO: contrato_saldo(p_contrato) lo lee la pantalla (ficha de la factura y editor). Una sola fuente, la misma
--   función que usa el tope: lo que se ve y lo que se hace valer no pueden diverger.
--
-- Forma de aplicar (reference_parchear_funcion_viva_con_marca): la definición viva NO es la del repo. Cada marca debe
-- aparecer EXACTAMENTE una vez o la migración falla; el centinela hace que aplicarla dos veces no haga nada.
-- Originales vivos guardados al pie de este fichero para poder revertir.

-- ── 1. Una sola cuenta de la cadena ──────────────────────────────────────────
create or replace function public._cadena_saldo(p_contrato uuid, p_excluir uuid default null)
returns table (raiz uuid, raiz_numero text, moneda text, precio numeric, sin_precio boolean,
               facturado numeric, total_facturas numeric, cobrado numeric)
language sql stable security definer set search_path = '' as $$
  with r as (
    select coalesce(c.contrato_padre_id, c.id) as id from public.contratos c where c.id = p_contrato
  ), ro as (
    select c.id, c.numero, c.moneda from public.contratos c join r on r.id = c.id
  ), ca as (
    select c.id, c.tipo, c.precio_total from public.contratos c, r
     where c.id = r.id or c.contrato_padre_id = r.id
  ), fa as (
    select f.id, f.total,
           coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total) as subtotal,
           coalesce((select sum(ra.importe_aplicado)
                       from public.recibi_aplicaciones ra
                       join public.facturas rc on rc.id = ra.recibi_id
                      where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0) as cobrado
      from public.facturas f
      join ca on ca.id = f.contrato_id, ro
     where f.tipo = 'factura' and not coalesce(f.anulada, false)
       and f.moneda is not distinct from ro.moneda
       and f.id is distinct from p_excluir
  )
  select ro.id, ro.numero, ro.moneda,
         (select sum(ca.precio_total) from ca where ca.tipo not like 'carta\_reserva%'),
         coalesce((select bool_or(ca.precio_total is null) from ca where ca.tipo not like 'carta\_reserva%'), true),
         coalesce((select sum(fa.subtotal) from fa), 0),
         coalesce((select sum(fa.total) from fa), 0),
         coalesce((select sum(fa.cobrado) from fa), 0)
    from ro;
$$;
revoke all on function public._cadena_saldo(uuid, uuid) from public, anon, authenticated, service_role;

-- ── 2. El tope de factura ────────────────────────────────────────────────────
create or replace function public._factura_tope_cadena(p_id uuid, p_contrato uuid, p_moneda text, p_subtotal numeric, p_tipo text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_raiz uuid; v_s record; v_ant numeric; v_tol numeric;
begin
  if p_tipo is distinct from 'factura' or p_contrato is null then return; end if;
  select coalesce(c.contrato_padre_id, c.id) into v_raiz from public.contratos c where c.id = p_contrato;
  if v_raiz is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('factura_tope:' || v_raiz::text, 0));
  select * into v_s from public._cadena_saldo(p_contrato, p_id);
  if v_s.raiz is null or v_s.moneda is distinct from p_moneda or v_s.sin_precio or coalesce(v_s.precio, 0) <= 0 then return; end if;
  v_tol := power(10::numeric, -public.lw_decimales(p_moneda));
  if p_id is not null then
    select coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total) into v_ant
      from public.facturas f where f.id = p_id;
    if v_ant is not null and p_subtotal <= v_ant + v_tol then return; end if;
  end if;
  if v_s.facturado + p_subtotal <= v_s.precio + v_tol then return; end if;
  if public.es_super_admin() then
    perform public.registra_privilegio(p_contrato, 'factura_sobre_tope',
      jsonb_build_object('raiz', v_s.raiz_numero, 'precio', v_s.precio, 'facturado_antes', v_s.facturado, 'documento', p_subtotal));
    return;
  end if;
  raise exception 'Con este documento se facturarían % y el precio acordado de % es %. Quedan % por facturar. Corrige el importe, o el precio del contrato si cambió.',
    v_s.facturado + p_subtotal, v_s.raiz_numero, v_s.precio, greatest(v_s.precio - v_s.facturado, 0)
    using errcode = '23514';
end $$;
revoke all on function public._factura_tope_cadena(uuid, uuid, text, numeric, text) from public, anon, authenticated, service_role;

-- ── 3. El saldo que lee la pantalla ──────────────────────────────────────────
create or replace function public.contrato_saldo(p_contrato uuid)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_s record; v_f jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  if not (public.es_super_admin() or (public.es_agente() and public.puede_ver_contrato(p_contrato))) then
    raise exception 'No puedes ver este contrato' using errcode = '42501';
  end if;
  select * into v_s from public._cadena_saldo(p_contrato, null);
  if v_s.raiz is null then
    raise exception 'Ese contrato ya no existe' using errcode = 'P0002';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'numero', f.numero, 'total', f.total,
           'cobrado', coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                                  join public.facturas rc on rc.id = ra.recibi_id
                                 where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0),
           'lineas', coalesce((select jsonb_agg(jsonb_build_object(
                         'descripcion', l->>'descripcion',
                         'importe', public.lw_parse_importe(l->>'importe')))
                       from jsonb_array_elements(case when jsonb_typeof(f.datos->'lineas') = 'array'
                                                      then f.datos->'lineas' else '[]'::jsonb end) l), '[]'::jsonb))
         order by f.numero), '[]'::jsonb)
    into v_f
    from public.facturas f
   where f.contrato_id = p_contrato and f.tipo = 'factura' and not coalesce(f.anulada, false);
  return jsonb_build_object(
    'cadena', v_s.raiz_numero, 'moneda', v_s.moneda, 'precio', v_s.precio, 'sin_precio', v_s.sin_precio,
    'facturado', v_s.facturado, 'cobrado', v_s.cobrado,
    'por_cobrar', v_s.total_facturas - v_s.cobrado,
    'por_facturar', case when v_s.sin_precio or coalesce(v_s.precio, 0) <= 0 then null
                         else greatest(v_s.precio - v_s.facturado, 0) end,
    'facturas', v_f);
end $$;
revoke all on function public.contrato_saldo(uuid) from public, anon;
grant execute on function public.contrato_saldo(uuid) to authenticated;

-- ── 4. Parche de factura_guarda y guardar_recibi sobre la definición VIVA ────
do $do$
declare
  d text; n int;
  m1 constant text := E'  v_datos := jsonb_set(v_datos, ''{totales}'', v_tot, true);\n';
  m2 constant text := E'  v_factura_proyecto uuid;\nbegin\n';
  m3 constant text := E'  for v_aplicacion in select * from jsonb_array_elements(p_aplicaciones) loop\n';
  m4 constant text := E'    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)\n';
begin
  -- factura_guarda
  d := pg_get_functiondef('public.factura_guarda(uuid,jsonb)'::regprocedure);
  if position('_factura_tope_cadena' in d) = 0 then
    n := (length(d) - length(replace(d, m1, ''))) / length(m1);
    if n <> 1 then raise exception 'factura_guarda: la marca aparece % veces (debe ser 1); no se parchea', n; end if;
    d := replace(d, m1, m1 || E'  perform public._factura_tope_cadena(p_id, v_contrato, v_moneda, (v_tot->>''subtotal'')::numeric, v_tipo);\n');
    execute d;
  end if;

  -- guardar_recibi
  d := pg_get_functiondef('public.guardar_recibi(uuid,jsonb,jsonb)'::regprocedure);
  if position('v_pend_factura' in d) = 0 then
    foreach n in array array[(length(d) - length(replace(d, m2, ''))) / length(m2),
                             (length(d) - length(replace(d, m3, ''))) / length(m3),
                             (length(d) - length(replace(d, m4, ''))) / length(m4)] loop
      if n <> 1 then raise exception 'guardar_recibi: una marca aparece % veces (debe ser 1); no se parchea', n; end if;
    end loop;
    d := replace(d, m2, E'  v_factura_proyecto uuid;\n  v_importe_aplic numeric;\n  v_pend_factura numeric;\n  v_moneda_factura text;\nbegin\n');
    d := replace(d, m3, E'  perform 1 from public.facturas fl\n   where fl.id in (select (a->>''factura_id'')::uuid from jsonb_array_elements(p_aplicaciones) a)\n   order by fl.id for update;\n' || m3);
    d := replace(d, m4,
      E'    v_importe_aplic := (v_aplicacion->>''importe'')::numeric;\n' ||
      E'    if v_importe_aplic is null or v_importe_aplic <= 0 then\n' ||
      E'      raise exception ''el importe que se aplica a la factura % tiene que ser mayor que cero'', coalesce(v_factura_numero, ''?'') using errcode = ''23514'';\n' ||
      E'    end if;\n' ||
      E'    select f.total - coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra\n' ||
      E'                                 join public.facturas rc on rc.id = ra.recibi_id\n' ||
      E'                                where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0), f.moneda\n' ||
      E'      into v_pend_factura, v_moneda_factura from public.facturas f where f.id = v_factura_id;\n' ||
      E'    if v_importe_aplic > v_pend_factura + power(10::numeric, -public.lw_decimales(v_moneda_factura)) then\n' ||
      E'      raise exception ''la factura % solo tiene % pendiente de cobro y este recibí le aplica %'', coalesce(v_factura_numero, ''?''), v_pend_factura, v_importe_aplic using errcode = ''23514'';\n' ||
      E'    end if;\n' || m4);
    execute d;
  end if;
end $do$;

-- Originales vivos (5-oct-2026) para revertir: factura_guarda pierde solo la línea
--   `perform public._factura_tope_cadena(...)`; guardar_recibi pierde las variables v_importe_aplic / v_pend_factura /
--   v_moneda_factura, el `perform 1 ... for update` previo al bucle y el bloque de comprobación antes del insert en
--   recibi_aplicaciones. Las definiciones completas están en pg_get_functiondef del 5-oct y en la revisión previa #206.
