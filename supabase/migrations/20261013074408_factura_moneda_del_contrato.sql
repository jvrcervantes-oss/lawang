-- LAW-553 (13-oct-2026): la moneda de un documento con contrato la decide el CONTRATO, no el navegador; y el tope de
-- facturas de una venta se mide por cadena Y moneda (nunca se salta por ir en otra moneda).
--
-- Qué pasaba (verificado contra pg_get_functiondef vivo el 13-oct). factura_guarda guardaba `p_factura->>'moneda'`
-- tal cual, y _factura_tope_cadena hacía `return` (sin comprobar nada) en cuanto la moneda de la factura no era la de
-- la raíz de la cadena (`v_s.moneda is distinct from p_moneda`); _cadena_saldo solo suma facturas en la moneda de la
-- raíz. Mandar IDR desde el navegador sobre una venta en EUR dejaba facturar sin tope. guardar_recibi y
-- factura_vencimiento_emite también guardan la moneda que reciben. Contra «No te creas NADA del front-end» (CLAUDE.md).
--
-- Medido en producción el 13-oct antes de aplicar:
--   · 0 documentos (factura, proforma, recibí; anulados o no) con moneda distinta de la de su contrato o de su raíz.
--     Facturas: 535 EUR y 6 IDR (todas sobre contratos IDR). Moneda nula: 0. Fuera de EUR/USD/AUD/IDR: 0.
--   · Cadenas en IDR: 2 reservas_parcela raíz en IDR con 2 construcciones hijas en IDR. 0 hijos en moneda distinta de
--     su raíz.
--   · 5 contratos con moneda nula: 4 Hak Sewa sueltos (HS00003-6) y 1 Poder hijo de una raíz sin moneda; 0 documentos.
--   · Hak Sewa hijos (HS00007, HS00012): moneda EUR heredada del Bloqueo (trg_contrato_moneda_desde_unidad, paso 3),
--     sin precio_total; su precio va en datos.fields.hsn_precio_rp, en Rp según la plantilla, y en texto libre
--     («30000000», «64500», «30.000.000 IDR», vacío). 0 documentos sobre ningún Hak Sewa.
--   · contratos.tipo_cambio_idr NO existe (solo solicitudes_pago_retencion.tipo_cambio_idr): no hay tipo de cambio en el
--     contrato, así que «contar la factura convertida» exigiría inventar una fuente. Descartado: tope por moneda.
--   → Este cambio no deja inválido ningún documento emitido.
--
-- Qué cambia:
--   1. _factura_moneda_valida(contrato, moneda, registra): la moneda de un documento con contrato tiene que ser
--      coalesce(moneda del contrato, moneda de su raíz). Distinta u omitida → error en llano, SIN sobrescribirla en
--      silencio (factura_totales, lw_decimales y el cuadre con la pantalla ya se calcularon con la moneda recibida: IDR
--      no lleva decimales y EUR sí). Contrato y raíz sin moneda → error. Integridad, no tope: sin salida de super_admin.
--      Además, un documento sobre un Hak Sewa (hak_sewa_notario) se para —salvo super_admin, con rastro
--      'documento_sobre_hak_sewa'— mientras el owner no decida en qué moneda y contra qué precio se factura (LAW-550):
--      su contrato figura en EUR por herencia y su precio va en rupias en texto libre, así que facturarlo en EUR
--      obligaría a poner una cifra en rupias con etiqueta EUR (revisión previa de Administración, 13-oct). Hoy: 0
--      documentos.
--   2. Trigger trg_01_moneda_del_contrato BEFORE INSERT OR UPDATE ON facturas: aplica (1) a TODOS los escritores
--      (factura_guarda, guardar_recibi, factura_vencimiento_emite, los que reasignan contrato). En UPDATE solo si
--      cambia la moneda o el contrato (un documento viejo no se bloquea al tocar otra columna); y no deja cambiar la
--      moneda de un documento con cobros aplicados. Nombre con 01: los BEFORE corren por orden alfabético, así que
--      para antes de trg_set_factura_numero y un rechazo NO gasta número de la serie fiscal.
--   3. Constraint facturas_moneda_admitida: moneda no nula y de la lista cerrada EUR, USD, AUD, IDR (las que ofrecen
--      los desplegables de intranet/facturas/index.html:765 y intranet/v4/assets/editores.js:3890). Un único sitio:
--      añadir una moneda es cambiar esta constraint.
--   4. _cadena_saldo_en(contrato, moneda, excluir): la regla de _cadena_saldo (20261013062339) para la moneda pedida.
--      «cuenta» = no es carta de reserva, no es (hijo y pieza que acompaña), y su moneda es la pedida; facturado =
--      facturas en esa moneda sobre cualquier miembro de la cadena. Para la moneda de la raíz es literalmente la misma
--      regla (la raíz siempre está en su moneda; un hijo cuenta si su moneda no es distinta de la de la raíz), y
--      _cadena_saldo pasa a ser su envoltorio con la moneda de la raíz: misma firma, mismo resultado (comprobado cadena
--      a cadena en producción antes de aplicar), así que contrato_saldo (pantalla) no cambia.
--   5. _factura_tope_cadena: ya no se salta la otra moneda. En la moneda de la raíz, la regla de siempre (incluido «sin
--      precio → no hay tope»: 12 contratos sin precio_total). En otra moneda (un hijo con moneda propia), tope contra
--      el precio de los miembros de la cadena en esa moneda; si no hay ninguno con precio, se RECHAZA (ante un dato
--      que no debería estar, el tope se queda estrecho, criterio de 20261013062019); super_admin pasa con
--      registra_privilegio 'factura_sobre_tope', como hoy. La edición que no sube el importe solo se exime si además
--      sigue en la misma raíz y la misma moneda.
--   6. factura_guarda: llama a (1) justo después de las comprobaciones de permiso, antes de calcular totales y tope,
--      para que el mensaje sea el de la moneda y no otro. Resto del cuerpo idéntico al vivo
--      (20261008202000_f2_b2_2_facturas_por_empresa).
--   7. Trigger zz_00_contrato_moneda_con_documentos en contratos: la moneda efectiva de un contrato con documentos
--      vivos no cambia por debajo (trg_contrato_moneda_desde_unidad la recalcula en cada guardado), ni la de un
--      padre cuyos hijos sin moneda la heredan; y un contrato con facturas vivas no se cuelga de otra venta salvo
--      super_admin con rastro 'cambia_venta_con_facturas' (sacaría sus facturas de un tope y las metería en otro).
--   8. factura_vencimiento_emite (robot): pasa por _factura_tope_cadena. La edge factura-vencimiento manda la moneda
--      de la columna del contrato (antes `f.moneda || ct.moneda`, con f = datos.fields; 2 contratos, RP00169 y
--      CC00096, tienen la columna en IDR y los campos en EUR: LAW-561, del owner).
--   (2 a 8 vienen de la revisión previa de Seguridad y Administración del 13-oct, #305.)
--
-- Hallazgo al probar (13-oct): contrato_eventos_evento_check NO admite 'factura_sobre_tope' (ni los dos eventos nuevos
-- de aquí, 'documento_sobre_hak_sewa' y 'cambia_venta_con_facturas'). Desde 20261005210000 la salida del super_admin
-- sobre el tope revienta con esa constraint en vez de dejar rastro: falla CERRADA (nadie se salta el tope), pero el
-- super_admin tampoco. Ampliar la lista exige DROP CONSTRAINT, que en Lawang solo abre el owner (no_destruir.py):
-- va aparte, en contracts/sql/contrato_eventos_privilegios.sql (sin aplicar: lo aplica el owner), con fila en contexto/pendientes.md.
-- Hasta entonces las tres salidas del super_admin de esta migración fallan cerradas igual.
--
-- No cubre (límites con dueño): no hay tope TOTAL entre monedas de una misma venta (no puede haberlo sin tipo de
-- cambio); y el Hak Sewa queda parado hasta LAW-550. ERP maestro: ya exige «una operación, una moneda» con su trigger
-- (erp/migraciones/20260925090000_operacion_nucleo.sql:196) y no tiene _factura_tope_cadena; nada que portar.
--
-- Prueba: supabase/pruebas/factura_moneda_del_contrato.sql (transacción que acaba en raise, por perfiles; sin rastro).
--
-- Vuelta atrás (sin pérdida de datos), en este orden:
--   drop trigger trg_01_moneda_del_contrato on public.facturas;
--   drop trigger zz_00_contrato_moneda_con_documentos on public.contratos;
--   alter table public.facturas drop constraint facturas_moneda_admitida;
--   factura_vencimiento_emite → la de 20260926160000_factura_vencimiento_atomica.sql (INVOKER, sin la llamada al tope);
--   factura_guarda      → la definición de 20261008202000_f2_b2_2_facturas_por_empresa.sql (sin la línea perform
--                         public._factura_moneda_valida(...));
--   _factura_tope_cadena → la de 20261005220000_saldo_subtotal_y_tope_cambia_cadena.sql;
--   _cadena_saldo       → la de 20261013062339_cadena_saldo_hijo_sin_moneda_fuera.sql;
--   drop function public.trg_factura_moneda_del_contrato(), public.trg_contrato_moneda_con_documentos(),
--                 public._factura_moneda_valida(uuid, text, boolean), public._cadena_saldo_en(uuid, text, uuid);

-- 1 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public._factura_moneda_valida(p_contrato uuid, p_moneda text, p_registra boolean)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
-- volatile (no stable): con p_registra escribe el rastro del super_admin (registra_privilegio hace insert)
declare v_num text; v_tipo text; v_mon text; v_padre uuid;
begin
  if p_contrato is null then
    if p_moneda is null then
      raise exception 'Falta la moneda del documento' using errcode = '23514';
    end if;
    return p_moneda;
  end if;
  -- for share: si a la vez alguien cambia la moneda del contrato o de su raíz, las dos operaciones van en serie
  -- (revisión previa de Seguridad, 13-oct); la del contrato la para además trg_zz_contrato_moneda_con_documentos.
  select c.numero, c.tipo, c.moneda, c.contrato_padre_id into v_num, v_tipo, v_mon, v_padre
    from public.contratos c where c.id = p_contrato for share;
  if not found then
    return p_moneda;   -- contrato inexistente: lo para la FK de facturas.contrato_id
  end if;
  if v_padre is not null then
    perform 1 from public.contratos r where r.id = v_padre for share;
    if v_mon is null then
      select r.moneda into v_mon from public.contratos r where r.id = v_padre;
    end if;
  end if;
  if v_mon is null then
    raise exception 'El contrato % no tiene moneda: ponla en el contrato antes de emitir documentos sobre él', v_num
      using errcode = '23514';
  end if;
  if p_moneda is distinct from v_mon then
    raise exception 'El contrato % va en % y el documento venía en %. Pon la moneda del documento en % (los importes se escriben en esa moneda) y vuelve a guardar.',
      v_num, v_mon, coalesce(p_moneda, 'ninguna'), v_mon using errcode = '23514';
  end if;
  if v_tipo = 'hak_sewa_notario' then
    if public.es_super_admin_de(public._empresa_doc(null::uuid, p_contrato)) then
      if p_registra then
        perform public.registra_privilegio(p_contrato, 'documento_sobre_hak_sewa',
          jsonb_build_object('contrato', v_num, 'moneda', p_moneda));
      end if;
    else
      raise exception 'Los documentos de un Hak Sewa (%) están parados hasta que se decida en qué moneda y contra qué precio se facturan: el contrato figura en % y su precio va en rupias. Si es urgente, lo emite un super admin.',
        v_num, v_mon using errcode = '23514';
    end if;
  end if;
  return v_mon;
end $function$;
revoke all on function public._factura_moneda_valida(uuid, text, boolean) from public, anon, authenticated, service_role;

-- 2 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.trg_factura_moneda_del_contrato()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' or new.moneda is distinct from old.moneda or new.contrato_id is distinct from old.contrato_id then
    perform public._factura_moneda_valida(new.contrato_id, new.moneda, true);
  end if;
  -- valida_recibi_aplicacion solo salta al tocar recibi_aplicaciones: cambiar la moneda de un documento ya aplicado
  -- (como factura o como recibí) dejaría la aplicación en dos monedas.
  if tg_op = 'UPDATE' and new.moneda is distinct from old.moneda
     and exists (select 1 from public.recibi_aplicaciones ra where ra.factura_id = new.id or ra.recibi_id = new.id) then
    raise exception 'El documento % ya tiene cobros aplicados en %: su moneda no se cambia', old.numero, old.moneda
      using errcode = '23514';
  end if;
  return new;
end $function$;
revoke all on function public.trg_factura_moneda_del_contrato() from public, anon, authenticated, service_role;

-- Sin lista de columnas (Seguridad, 13-oct): un `update of` solo mira las columnas del SET y no vería lo que cambiara
-- otro trigger BEFORE. Y se llama trg_01 (no zz_) a propósito: los BEFORE corren por orden de nombre y tiene que ir
-- ANTES de trg_set_factura_numero, o un rechazo gastaría número de la serie fiscal (nextval no se deshace). Hoy
-- ningún BEFORE de facturas asigna new.moneda ni new.contrato_id (comprobado en sus definiciones, 13-oct); uno nuevo
-- que lo haga tiene que llamarse por debajo de trg_01 o volver a llamar a _factura_moneda_valida.
create trigger trg_01_moneda_del_contrato
  before insert or update on public.facturas
  for each row execute function public.trg_factura_moneda_del_contrato();

-- 3 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
alter table public.facturas add constraint facturas_moneda_admitida
  check (moneda is not null and moneda in ('EUR', 'USD', 'AUD', 'IDR'));

-- 4 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public._cadena_saldo_en(p_contrato uuid, p_moneda text, p_excluir uuid default null::uuid)
 returns table(raiz uuid, raiz_numero text, moneda text, precio numeric, sin_precio boolean, facturado numeric, total_facturas numeric, cobrado numeric)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with r as (
    select coalesce(c.contrato_padre_id, c.id) as id from public.contratos c where c.id = p_contrato
  ), ro as (
    select c.id, c.numero from public.contratos c join r on r.id = c.id
  ), ca as (
    -- cuenta: entra en el precio de la cadena EN ESTA MONEDA. Fuera: las cartas de reserva; los hijos que acompañan a
    -- la venta (gemela de PIEZAS_ACOMPANAN en contracts/assets/operaciones-cuentas.js), tengan o no precio; y lo que va
    -- en otra moneda (para la moneda de la raíz: los hijos en otra moneda o sin ella, como en 20261013062339).
    select c.id, c.tipo, c.precio_total,
           c.tipo not like 'carta\_reserva%'
           and not (c.id <> r.id and c.tipo in ('poa', 'hak_sewa_notario', 'adenda'))
           and c.moneda is not distinct from p_moneda as cuenta
      from public.contratos c, r
     where c.id = r.id or c.contrato_padre_id = r.id
  ), fa as (
    select f.id, f.total,
           coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total) as subtotal,
           coalesce((select sum(ra.importe_aplicado)
                       from public.recibi_aplicaciones ra
                       join public.facturas rc on rc.id = ra.recibi_id
                      where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0) as cobrado
      from public.facturas f
      join ca on ca.id = f.contrato_id
     where f.tipo = 'factura' and not coalesce(f.anulada, false)
       and f.moneda is not distinct from p_moneda
       and f.id is distinct from p_excluir
  )
  select ro.id, ro.numero, p_moneda,
         (select sum(ca.precio_total) from ca where ca.cuenta),
         coalesce((select bool_or(ca.precio_total is null) from ca where ca.cuenta), true),
         coalesce((select sum(fa.subtotal) from fa), 0),
         coalesce((select sum(fa.total) from fa), 0),
         coalesce((select sum(fa.cobrado) from fa), 0)
    from ro;
$function$;
revoke all on function public._cadena_saldo_en(uuid, text, uuid) from public, anon, authenticated, service_role;

-- _cadena_saldo: envoltorio con la moneda de la raíz. Misma firma; create or replace conserva el revoke de
-- 20261005210000, y se repite por si acaso.
create or replace function public._cadena_saldo(p_contrato uuid, p_excluir uuid default null::uuid)
 returns table(raiz uuid, raiz_numero text, moneda text, precio numeric, sin_precio boolean, facturado numeric, total_facturas numeric, cobrado numeric)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select s.*
    from public.contratos c
    join public.contratos r on r.id = coalesce(c.contrato_padre_id, c.id)
    cross join lateral public._cadena_saldo_en(p_contrato, r.moneda, p_excluir) s
   where c.id = p_contrato;
$function$;
revoke all on function public._cadena_saldo(uuid, uuid) from public, anon, authenticated, service_role;

-- 5 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public._factura_tope_cadena(p_id uuid, p_contrato uuid, p_moneda text, p_subtotal numeric, p_tipo text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_raiz uuid; v_raiz_moneda text; v_raiz_ant uuid; v_moneda_ant text; v_s record; v_ant numeric; v_tol numeric;
  v_otra boolean;
begin
  if p_tipo is distinct from 'factura' or p_contrato is null then return; end if;
  select coalesce(c.contrato_padre_id, c.id) into v_raiz from public.contratos c where c.id = p_contrato;
  if v_raiz is null then return; end if;
  select r.moneda into v_raiz_moneda from public.contratos r where r.id = v_raiz;
  perform pg_advisory_xact_lock(hashtextextended('factura_tope:' || v_raiz::text, 0));
  select * into v_s from public._cadena_saldo_en(p_contrato, p_moneda, p_id);
  if v_s.raiz is null then return; end if;
  v_otra := p_moneda is distinct from v_raiz_moneda;
  v_tol := power(10::numeric, -public.lw_decimales(p_moneda));

  if v_s.sin_precio or coalesce(v_s.precio, 0) <= 0 then
    if not v_otra then return; end if;   -- moneda de la raíz sin precio: como siempre, no hay tope
    if public.es_super_admin_de(public._empresa_doc(null::uuid, p_contrato)) then
      perform public.registra_privilegio(p_contrato, 'factura_sobre_tope',
        jsonb_build_object('raiz', v_s.raiz_numero, 'moneda', p_moneda, 'motivo', 'sin precio en esta moneda',
                           'facturado_antes', v_s.facturado, 'documento', p_subtotal));
      return;
    end if;
    raise exception 'Esta factura va en % y la venta % no tiene ningún contrato con precio en %: no hay contra qué comprobarla. Pon el precio en el contrato que va en %, o factura en % sobre la venta.',
      p_moneda, v_s.raiz_numero, p_moneda, p_moneda, coalesce(v_raiz_moneda, 'su moneda')
      using errcode = '23514';
  end if;

  if p_id is not null then
    select coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total), f.moneda,
           (select coalesce(c.contrato_padre_id, c.id) from public.contratos c where c.id = f.contrato_id)
      into v_ant, v_moneda_ant, v_raiz_ant
      from public.facturas f where f.id = p_id;
    if v_ant is not null and v_raiz_ant is not distinct from v_raiz and v_moneda_ant is not distinct from p_moneda
       and p_subtotal <= v_ant + v_tol then return; end if;
  end if;
  if v_s.facturado + p_subtotal <= v_s.precio + v_tol then return; end if;
  if public.es_super_admin_de(public._empresa_doc(null::uuid, p_contrato)) then
    perform public.registra_privilegio(p_contrato, 'factura_sobre_tope',
      jsonb_build_object('raiz', v_s.raiz_numero, 'moneda', p_moneda, 'precio', v_s.precio,
                         'facturado_antes', v_s.facturado, 'documento', p_subtotal));
    return;
  end if;
  raise exception 'Con este documento se facturarían % % y el precio acordado de % en % es %. Quedan % por facturar. Corrige el importe, o el precio del contrato si cambió.',
    v_s.facturado + p_subtotal, p_moneda, v_s.raiz_numero, p_moneda, v_s.precio, greatest(v_s.precio - v_s.facturado, 0)
    using errcode = '23514';
end $function$;
revoke all on function public._factura_tope_cadena(uuid, uuid, text, numeric, text) from public, anon, authenticated, service_role;

-- 6 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- factura_guarda: idéntica a la viva (20261008202000_f2_b2_2_facturas_por_empresa) salvo el bloque marcado LAW-553.
create or replace function public.factura_guarda(p_id uuid, p_factura jsonb)
 returns table(id uuid, numero text, total numeric)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_old public.facturas%rowtype;
  v_tipo text := coalesce(nullif(p_factura->>'tipo', ''), 'factura');
  v_contrato uuid := nullif(p_factura->>'contrato_id', '')::uuid;
  v_client uuid := nullif(p_factura->>'client_id', '')::uuid;
  v_moneda text := nullif(p_factura->>'moneda', '');
  v_datos jsonb := coalesce(p_factura->'datos', '{}'::jsonb);
  v_pantalla numeric := public.lw_parse_importe(p_factura->>'total');
  v_tot jsonb; v_total numeric; v_id uuid; v_num text; v_proy uuid; v_autor text; n int;
  v_rest boolean := public.alcance_restringido() and not public.es_admin();
  v_pnombre text := nullif(p_factura->>'proyecto_nombre', '');
  v_pid uuid; v_emp text;
begin
  if (select auth.uid()) is null then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  if v_tipo = 'recibi' then
    raise exception 'Un recibí se guarda con guardar_recibi, no aquí' using errcode = '22023';
  end if;
  if v_tipo not in ('factura', 'proforma') then
    raise exception 'Tipo de documento desconocido: %', v_tipo using errcode = '22023';
  end if;
  if not public._puede_herr('facturas') then
    raise exception 'Emitir o editar facturas exige la herramienta «Facturas»' using errcode = '42501';
  end if;
  if v_contrato is not null then
    if not exists (select 1 from public.contratos c
                    where c.id = v_contrato and public.puede_ver_contrato(c.id)) then
      raise exception 'No puedes emitir un documento sobre un contrato que no ves' using errcode = '42501';
    end if;
  end if;
  if v_client is not null then
    if not (
         (v_contrato is not null and exists (select 1 from public.contrato_compradores cc
                                              where cc.contrato_id = v_contrato and cc.client_id = v_client))
      or exists (select 1 from public.clients k
                  where k.id = v_client and public.cliente_visible(k.propietario, k.id))) then
      raise exception 'Ese cliente no es comprador de este contrato ni un cliente que veas' using errcode = '42501';
    end if;
  end if;

  if v_rest then
    if v_contrato is not null then
      select c.proyecto_id into v_pid from public.contratos c where c.id = v_contrato;
      select pr.nombre into v_pnombre from public.proyectos pr where pr.id = v_pid;
    else
      select pr.id into v_pid from public.proyectos pr where pr.nombre = v_pnombre;
    end if;
    v_emp := public._empresa_doc(v_pid, v_contrato);
    if v_emp is null or not public.puede_empresa(v_emp) then
      raise exception 'Ese documento no es de ninguna de tus empresas: elige un contrato o un proyecto de las tuyas' using errcode = '42501';
    end if;
    if (p_id is null or (p_factura->>'sociedad') is distinct from (select f.sociedad from public.facturas f where f.id = p_id))
       and not exists (select 1 from public.empresas e where e.clave = v_emp and e.sociedad_clave = p_factura->>'sociedad') then
      raise exception 'Ese documento tiene que salir por la sociedad de la empresa del proyecto' using errcode = '42501';
    end if;
  end if;

  -- LAW-553: la moneda la decide el contrato. trg_01_moneda_del_contrato lo vuelve a exigir al escribir (y deja el
  -- rastro del super_admin); aquí se adelanta para que el mensaje sea el de la moneda y no el del tope o el cuadre.
  perform public._factura_moneda_valida(v_contrato, v_moneda, false);

  if jsonb_typeof(v_datos->'fields') = 'object' then
    v_datos := jsonb_set(v_datos, '{fields}', (v_datos->'fields') - 'banco_de_servidor');
  end if;

  v_tot := public.factura_totales(v_datos->'lineas', v_moneda, v_datos->'fields'->>'imp_pct');
  v_total := (v_tot->>'total')::numeric;
  if (v_tot->>'pct')::numeric not between 0 and 100 then
    raise exception 'El impuesto tiene que estar entre 0 y 100 %%' using errcode = '22023';
  end if;
  if (v_tot->>'subtotal')::numeric <= 0 then
    raise exception 'El documento no tiene importe (un total negativo es una rectificativa, no una factura)'
      using errcode = '22023';
  end if;
  if v_pantalla is null then
    raise exception 'Falta el total que se ve en pantalla: recarga la página y vuelve a guardar' using errcode = '22023';
  end if;
  if abs(v_pantalla - v_total) > power(10::numeric, -public.lw_decimales(v_moneda)) then
    raise exception 'El total no cuadra: la pantalla dice % y las líneas suman %. Recarga la página y vuelve a guardar.',
      v_pantalla, v_total using errcode = '22023';
  end if;
  v_datos := jsonb_set(v_datos, '{totales}', v_tot, true);
  perform public._factura_tope_cadena(p_id, v_contrato, v_moneda, (v_tot->>'subtotal')::numeric, v_tipo);

  if p_id is null then
    insert into public.facturas as f
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id, client_id,
       total, moneda, fecha_emision, datos, justificantes)
    values
      (v_tipo, p_factura->>'sociedad', nullif(p_factura->>'cliente_nombre', ''),
       v_pnombre, nullif(p_factura->>'contrato_numero', ''),
       v_contrato, v_client, v_total, v_moneda, nullif(p_factura->>'fecha_emision', '')::date,
       v_datos, '[]'::jsonb)
    returning f.id, f.numero into v_id, v_num;
  else
    select * into v_old from public.facturas f where f.id = p_id for update;
    if not found then
      raise exception 'Ese documento ya no existe' using errcode = 'P0002';
    end if;
    if v_old.tipo = 'recibi' then
      raise exception 'Un recibí se edita con guardar_recibi, no aquí' using errcode = '22023';
    end if;
    if not public._factura_puede_editar(v_old) then
      raise exception 'No puedes editar este documento (anulado, o no es tuyo ni de tu proyecto)' using errcode = '42501';
    end if;
    if v_old.enviada and v_old.tipo = 'factura' then
      raise exception 'La factura % ya se envió: no se edita (ni cliente, ni empresa, ni fecha, ni importes). Se corrige con una rectificativa.', v_old.numero
        using errcode = '42501';
    end if;
    if v_old.enviada and (v_total is distinct from v_old.total
                          or v_moneda is distinct from v_old.moneda
                          or (v_datos->'lineas') is distinct from (v_old.datos->'lineas')) then
      raise exception 'El documento % ya se envió: sus importes no se cambian, se emite una rectificativa', v_old.numero
        using errcode = '42501';
    end if;
    update public.facturas f set
      tipo = v_tipo, sociedad = p_factura->>'sociedad',
      cliente_nombre = nullif(p_factura->>'cliente_nombre', ''),
      proyecto_nombre = v_pnombre,
      contrato_numero = nullif(p_factura->>'contrato_numero', ''),
      contrato_id = v_contrato, client_id = v_client, total = v_total, moneda = v_moneda,
      fecha_emision = nullif(p_factura->>'fecha_emision', '')::date, datos = v_datos
    where f.id = p_id
    returning f.id, f.numero, f.proyecto_id, f.creado_por into v_id, v_num, v_proy, v_autor;
    get diagnostics n = row_count;
    if n <> 1 then
      raise exception 'No se ha guardado (0 filas)' using errcode = 'P0002';
    end if;
    if not (public.es_super_admin_de(public._empresa_doc(v_proy, v_contrato))
            or (public._puede_herr('facturas')
                and (public.es_suyo(v_autor) or public.es_manager_de(v_proy) or public._sm_ve_venta(v_contrato)
                     or public.es_admin_de(public._empresa_doc(v_proy, v_contrato))))) then
      raise exception 'Con ese contrato el documento dejaría de ser tuyo o de tu proyecto' using errcode = '42501';
    end if;
  end if;
  return query select v_id, v_num, v_total;
end $function$;

-- 7 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- La moneda del CONTRATO no cambia por debajo de sus documentos (revisión previa de Seguridad, 13-oct). Sin esto,
-- trg_contrato_moneda_desde_unidad (BEFORE UPDATE sin lista de columnas, mientras el contrato no está firmado)
-- recalcula la moneda desde la parcela, la unidad o el padre en cualquier guardado: los documentos ya emitidos
-- quedarían en la moneda vieja, la cadena dejaría de contarlos y el tope de la nueva moneda empezaría en 0. Y
-- cambiar contrato_padre_id de un contrato con facturas las saca de una cadena (que recupera margen) y las mete en
-- otra (sin pasar su tope). Medido el 13-oct: 153 contratos sin firmar con documentos vivos, 0 cambiarían de
-- moneda al volver a guardarse (réplica en SELECT de los tres pasos de fn_contrato_moneda_desde_unidad).
-- zz_00: corre después de trg_contrato_moneda_desde_unidad (orden de nombre) y antes de zz_contrato_datos_fields,
-- que no toca la moneda.
create or replace function public.trg_contrato_moneda_con_documentos()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_ant text; v_nueva text;
begin
  if new.contrato_padre_id is distinct from old.contrato_padre_id
     and exists (select 1 from public.facturas f
                  where f.contrato_id = new.id and f.tipo = 'factura' and not coalesce(f.anulada, false)) then
    if public.es_super_admin_de(public._empresa_doc(null::uuid, new.id)) then
      perform public.registra_privilegio(new.id, 'cambia_venta_con_facturas',
        jsonb_build_object('de', old.contrato_padre_id, 'a', new.contrato_padre_id));
    else
      raise exception 'El contrato % ya tiene facturas: no se cuelga de otra venta (sus facturas cambiarían de tope). Anúlalas antes, o pídeselo a un super admin.',
        old.numero using errcode = '23514';
    end if;
  end if;

  v_ant := coalesce(old.moneda, (select p.moneda from public.contratos p where p.id = old.contrato_padre_id));
  v_nueva := coalesce(new.moneda, (select p.moneda from public.contratos p where p.id = new.contrato_padre_id));
  if v_nueva is distinct from v_ant
     and exists (select 1 from public.facturas f where f.contrato_id = new.id and not coalesce(f.anulada, false)) then
    raise exception 'El contrato % tiene documentos en % y al guardarlo pasaría a %: la moneda de un contrato con documentos vivos no cambia. Revisa la moneda de su parcela o unidad, o anula los documentos antes.',
      old.numero, coalesce(v_ant, 'ninguna'), coalesce(v_nueva, 'ninguna') using errcode = '23514';
  end if;
  -- hijos sin moneda propia: heredan la de este contrato
  if new.moneda is distinct from old.moneda
     and exists (select 1 from public.contratos h join public.facturas f on f.contrato_id = h.id
                  where h.contrato_padre_id = new.id and h.moneda is null and not coalesce(f.anulada, false)) then
    raise exception 'El contrato % tiene contratos hijos sin moneda propia con documentos en %: su moneda no cambia.',
      old.numero, coalesce(old.moneda, 'ninguna') using errcode = '23514';
  end if;
  return new;
end $function$;
revoke all on function public.trg_contrato_moneda_con_documentos() from public, anon, authenticated, service_role;

create trigger zz_00_contrato_moneda_con_documentos
  before update on public.contratos
  for each row execute function public.trg_contrato_moneda_con_documentos();

-- 8 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- factura_vencimiento_emite (robot factura-vencimiento, solo service_role): pasa por el mismo tope que factura_guarda
-- (hasta hoy no tenía ninguno en la base) y bajo el mismo candado por raíz. Pasa a SECURITY DEFINER para poder
-- llamar a _factura_tope_cadena (sin execute para service_role); create or replace conserva su ACL (postgres y
-- service_role). Resto idéntico al vivo (20260926160000_factura_vencimiento_atomica). La moneda la sigue exigiendo
-- trg_01_moneda_del_contrato: la edge pasa a mandar la de la columna del contrato (antes, la de datos.fields).
create or replace function public.factura_vencimiento_emite(p_venc_id uuid, p_fila jsonb)
 returns table(id uuid, numero text, datos jsonb)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_contrato uuid;
  v_factura  uuid;
  f          public.facturas;
  n          int;
begin
  select cv.contrato_id, cv.factura_id into v_contrato, v_factura
    from public.contrato_vencimientos cv where cv.id = p_venc_id for update;
  if not found then
    raise exception 'vencimiento % no existe', p_venc_id using hint = 'sin_fila';
  end if;
  if v_factura is not null then
    raise exception 'vencimiento % ya tiene factura', p_venc_id using hint = 'ya_facturado';
  end if;

  -- primero la moneda (mismo mensaje que factura_guarda; el trigger lo vuelve a exigir al insertar), luego el tope
  perform public._factura_moneda_valida(v_contrato, p_fila->>'moneda', false);
  perform public._factura_tope_cadena(null, v_contrato, p_fila->>'moneda',
    coalesce(nullif(p_fila->'datos'->'totales'->>'subtotal', '')::numeric, (p_fila->>'total')::numeric),
    p_fila->>'tipo');

  insert into public.facturas (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
                               total, moneda, fecha_emision, datos)
  values (p_fila->>'tipo', p_fila->>'sociedad', p_fila->>'cliente_nombre', p_fila->>'proyecto_nombre',
          p_fila->>'contrato_numero', v_contrato, (p_fila->>'total')::numeric, p_fila->>'moneda',
          (p_fila->>'fecha_emision')::date, p_fila->'datos')
  returning * into f;

  update public.contrato_vencimientos cv set factura_id = f.id where cv.id = p_venc_id;
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'no se pudo marcar el vencimiento %', p_venc_id using hint = 'sin_fila';
  end if;

  return query select f.id, f.numero, f.datos;
end $function$;
revoke all on function public.factura_vencimiento_emite(uuid, jsonb) from public, anon, authenticated;
