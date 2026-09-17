-- El libro deja de perder señales: abono visible, exenta que no revive,
-- moneda/sociedad vigiladas y reconciliador que mira las tres rutas (17-sep-2026)
-- ============================================================================
-- Consulta de deploy del mismo dia. Seguridad, Administracion y Desarrollo, por
-- separado, cazaron la misma familia: el libro se defendia bien de la escritura
-- DIRECTA (grant por columna: el navegador solo toca estado/nota/revisar) y no
-- de la INDIRECTA -- cambiar el recibi, que el trigger obedece. El vector esta
-- poblado, no es teorico: 24 usuarios no-admin activos (16 agente, 7
-- sales_manager, 1 PM) y la policy de UPDATE de `facturas` deja al autor y a su
-- manager editar su propio recibi no anulado, `datos` incluido.
--
-- [1] EL ABONO NACIA YA ANULADO — el peor de todos, y lo vieron dos
--     departamentos a la vez. En la rama (a), el `update ... where id =
--     v_linea.id or linea_origen_id = v_linea.id` corre DESPUES de insertar el
--     abono, cuyo `linea_origen_id` ES `v_linea.id`: se marcaba a si mismo.
--     Consecuencia: la UI lo saca de `vivas`, lo pinta al 60% y le quita el
--     boton. Si el devengo estaba ya `facturada`, **el abono es exactamente la
--     nota de credito que hay que emitir, y era invisible**. Y el mes cerrado
--     encogia solo, que es justo lo que el libro append-only venia a evitar.
--     Mismo fallo en la ruta de borrado. Se acota con `tipo_linea <> 'abono'`.
--
-- [2] UN AJUSTE SOBRE UNA LINEA `exenta` NACIA `pendiente`. La rama (c) entra
--     por el `else` con cualquier estado distinto de pendiente, y `exenta` es
--     uno. El INSERT no pasaba `estado`, asi que tomaba el default: dinero que
--     el owner habia marcado como NO-venta (aporte de capital, traspaso entre
--     las dos PT) volvia a ser facturable en cuanto alguien corregia el recibi.
--     Ahora la exencion se hereda.
--
-- [3] SOLO SE VIGILABA LA BASE. El formulario de recibis ofrece EUR/USD/AUD/IDR
--     y `guardar_recibi` actualiza tambien `moneda` y `sociedad`. Corregir la
--     moneda dejaba la comision en la vieja (20.000 registrados «EUR» que eran
--     IDR = 100 € en vez de 0,01 €), y `descuadres()` no lo cazaba porque
--     recalcula con la moneda de la propia linea. Corregir la sociedad dejaba la
--     comision facturada a la PT equivocada para siempre, siendo `sociedad` la
--     clave de facturacion. Ahora las tres disparan.
--
-- [4] BAJAR LA BASE EN SILENCIO. Mientras la linea sigue `pendiente` --el
--     default hasta que administracion factura-- la rama (c) reescribia base e
--     importe EN SITIO sin marca. Un agente edita su recibi a la baja despues
--     del alta y la comision se encoge sin que nadie se entere. Ahora: si BAJA,
--     `revisar=true`. Si sube, no -- corregir al alza no le quita dinero a nadie
--     y marcarlo seria ruido diario.
--
-- [5] ANULAR SIN SEÑAL. La rama (a) marcaba `anulada` pero no `revisar`, aunque
--     la comision estuviera ya facturada o cobrada. Un agente puede anular su
--     propio recibi (`USING anulada = false`) y con eso revertia una comision ya
--     emitida sin que administracion lo viera. La asimetria lo delataba: la ruta
--     de BORRADO si ponia `revisar`. Ahora las dos.
--
-- [6] EL RECONCILIADOR SOLO MIRABA EL ALTA, y encima daba un falso positivo
--     permanente: aplicaba `round(base*pct/100)` a TODAS las lineas, pero en
--     `ajuste`/`abono` el importe es una DIFERENCIA de redondeos (con 0,5% y
--     bases 101->202, el ajuste vale 0,50 y el check esperaba 0,51). Un banner
--     rojo que no se puede limpiar se aprende a ignorar, y entonces ya no avisa
--     de nada. Ahora ese contador mira solo devengos, y hay tres contadores
--     nuevos para las rutas que no cubria ninguno.
--
-- [7] UN RECIBI DESANULADO NO PODIA VOLVER A DEVENGAR NI A MANO: `anulada` no
--     esta en el grant de UPDATE de `authenticated`, asi que reponerlo exigia
--     SQL contra produccion. Hoy 10 de 97 recibis estan anulados (10%), o sea
--     que desanular por error no es hipotetico. Se abre una RPC de super_admin
--     que lo repone dejando rastro.
--
-- destructivo-ok: CREATE OR REPLACE de tres funciones y una RPC nueva. Ningun
-- DROP, DELETE ni UPDATE de datos.

-- ── Cambios sobre un recibi que ya tiene devengo ─────────────────────────────
create or replace function public._comision_admin_cambio_recibi()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_linea        record;
  v_base         numeric;
  v_moneda       text;
  v_decimales    integer;
  v_nuevo        numeric;
  v_neto_imp     numeric;
  v_neto_base    numeric;
  v_cambia_base  boolean;
  v_cambia_mon   boolean;
  v_cambia_soc   boolean;
  v_baja         boolean;
begin
  if coalesce(new.tipo, '') <> 'recibi' and coalesce(old.tipo, '') <> 'recibi' then
    return new;
  end if;

  select * into v_linea
    from public.comision_admin_lineas l
   where l.recibi_id = new.id and l.tipo_linea = 'devengo'
   limit 1;

  -- Un recibi sin devengo (anterior al corte, o que acaba de cambiar de tipo) NO
  -- nace de un UPDATE. Si el flip factura->recibi fuera legitimo, sale como
  -- «recibi vivo sin linea» en comision_admin_descuadres().
  if v_linea.id is null then
    return new;
  end if;

  v_base   := coalesce((new.datos -> 'totales' ->> 'subtotal')::numeric, new.total, 0);
  v_moneda := coalesce(new.moneda, v_linea.moneda);

  -- ── (a) el recibi se anula -> ABONO por el NETO devengado ──────────────────
  if coalesce(new.anulada, false) and not v_linea.anulada then
    select coalesce(sum(l.importe), 0), coalesce(sum(l.base_total), 0)
      into v_neto_imp, v_neto_base
      from public.comision_admin_lineas l
     where (l.id = v_linea.id or l.linea_origen_id = v_linea.id)
       and l.tipo_linea in ('devengo', 'ajuste');

    if v_neto_imp <> 0 or v_neto_base <> 0 then
      insert into public.comision_admin_lineas (
        tipo_linea, linea_origen_id, recibi_id, recibi_numero, sociedad,
        contrato_id, proyecto_id, devengado_el, fecha_recibi,
        base_total, moneda, pct_aplicado, importe, tarifa_id, estado, revisar, nota, snapshot
      ) values (
        'abono', v_linea.id, new.id, v_linea.recibi_numero, v_linea.sociedad,
        v_linea.contrato_id, v_linea.proyecto_id, current_date, v_linea.fecha_recibi,
        - v_neto_base, v_linea.moneda, v_linea.pct_aplicado,
        - v_neto_imp, v_linea.tarifa_id,
        -- [2] una exencion se hereda: revertir dinero exento no lo vuelve cobrable
        case when v_linea.estado = 'exenta' then 'exenta' else 'pendiente' end,
        -- [5] si la comision ya estaba emitida, esto llama a una persona: quien
        -- anula el recibi puede ser el mismo agente que lo creo
        v_linea.estado not in ('pendiente', 'exenta'),
        'Abono automatico: el recibi se anulo.',
        jsonb_build_object('motivo', 'recibi_anulado', 'devengo_id', v_linea.id,
                           'estado_al_anular', v_linea.estado,
                           'neto_revertido', v_neto_imp, 'en', now())
      );
    end if;

    -- [1] `tipo_linea <> 'abono'`: sin esto el abono recien insertado se marcaba
    -- a si mismo como anulado (su linea_origen_id ES v_linea.id) y desaparecia
    -- del libro y de los KPI justo cuando es la nota de credito a emitir.
    update public.comision_admin_lineas
       set anulada = true,
           revisar = revisar or v_linea.estado not in ('pendiente', 'exenta'),
           actualizado_en = now()
     where (id = v_linea.id or linea_origen_id = v_linea.id)
       and tipo_linea <> 'abono';
    return new;
  end if;

  -- ── (b) un recibi anulado vuelve a la vida ─────────────────────────────────
  -- El devengo NO se repone solo: reponerlo es una decision de administracion.
  -- Se hace con comision_admin_repone_devengo(), que es de super_admin.
  if not coalesce(new.anulada, false) and v_linea.anulada then
    update public.comision_admin_lineas
       set revisar = true, actualizado_en = now(),
           nota = coalesce(nota || ' - ', '') || 'El recibi se desanulo: revisar si procede reponer el devengo.'
     where id = v_linea.id;
    return new;
  end if;

  -- ── (c) cambia algo que decide cuanto y a quien se cobra ───────────────────
  -- [3] No solo la base: la MONEDA decide el redondeo y el valor real, y la
  -- SOCIEDAD decide a cual de las dos PT se le factura.
  v_cambia_base := v_base is distinct from v_linea.base_total;
  v_cambia_mon  := upper(v_moneda) is distinct from upper(v_linea.moneda);
  v_cambia_soc  := new.sociedad is distinct from v_linea.sociedad;

  if (v_cambia_base or v_cambia_mon or v_cambia_soc) and not v_linea.anulada then
    v_baja := v_cambia_base and v_base < v_linea.base_total;

    if v_linea.estado in ('pendiente', 'exenta')
       and not exists (select 1 from public.comision_admin_lineas a
                        where a.linea_origen_id = v_linea.id) then
      -- Nadie la ha facturado y no cuelga nada de ella: se corrige en sitio, con
      -- SU pct congelado (nunca el de hoy) y con los decimales de la moneda que
      -- queda, no de la que habia.
      v_decimales := case when upper(v_moneda) = 'IDR' then 0 else 2 end;
      v_nuevo     := round(v_base * v_linea.pct_aplicado / 100, v_decimales);

      update public.comision_admin_lineas
         set base_total = v_base, importe = v_nuevo, moneda = v_moneda,
             sociedad = new.sociedad,
             recibi_numero = coalesce(new.numero, recibi_numero),
             contrato_id = new.contrato_id, proyecto_id = new.proyecto_id,
             fecha_recibi = new.fecha_emision,
             -- [4] bajar la base despues del alta es la forma barata de encoger
             -- la comision sin tocar el libro. Subirla no se marca: no le quita
             -- dinero a nadie y seria ruido diario.
             revisar = revisar or v_baja or v_cambia_mon,
             nota = case
               when v_baja then coalesce(nota || ' - ', '') || 'El recibi bajo de ' ||
                                v_linea.base_total || ' a ' || v_base || ' despues del alta.'
               when v_cambia_mon then coalesce(nota || ' - ', '') || 'El recibi cambio de moneda: ' ||
                                v_linea.moneda || ' -> ' || v_moneda || '.'
               else nota end,
             actualizado_en = now()
       where id = v_linea.id;

    elsif v_cambia_base then
      -- Ya facturada/cobrada: el dinero emitido no se toca, se anota la
      -- DIFERENCIA contra lo devengado hasta ahora. Se queda en la moneda de la
      -- linea --que es la que se facturo-- y con SUS decimales; si ademas cambio
      -- la moneda, eso es una incoherencia que resuelve una persona, no una
      -- conversion automatica a un cambio inventado.
      v_decimales := case when upper(v_linea.moneda) = 'IDR' then 0 else 2 end;
      v_nuevo     := round(v_base * v_linea.pct_aplicado / 100, v_decimales);

      select coalesce(sum(l.importe), 0), coalesce(sum(l.base_total), 0)
        into v_neto_imp, v_neto_base
        from public.comision_admin_lineas l
       where (l.id = v_linea.id or l.linea_origen_id = v_linea.id)
         and l.tipo_linea in ('devengo', 'ajuste');

      insert into public.comision_admin_lineas (
        tipo_linea, linea_origen_id, recibi_id, recibi_numero, sociedad,
        contrato_id, proyecto_id, devengado_el, fecha_recibi,
        base_total, moneda, pct_aplicado, importe, tarifa_id, estado, revisar, nota, snapshot
      ) values (
        'ajuste', v_linea.id, new.id, coalesce(new.numero, v_linea.recibi_numero), v_linea.sociedad,
        new.contrato_id, new.proyecto_id, current_date, new.fecha_emision,
        v_base - v_neto_base, v_linea.moneda, v_linea.pct_aplicado,
        v_nuevo - v_neto_imp, v_linea.tarifa_id,
        -- [2] la exencion se hereda: corregir el importe de un aporte de capital
        -- no lo convierte en una venta facturable
        case when v_linea.estado = 'exenta' then 'exenta' else 'pendiente' end,
        true,
        'Ajuste automatico: el recibi cambio de importe despues de que la comision dejara de estar pendiente.'
          || case when v_cambia_mon then ' OJO: tambien cambio de moneda (' || v_linea.moneda ||
                       ' -> ' || v_moneda || '); el ajuste se queda en la moneda facturada.' else '' end,
        jsonb_build_object('motivo', 'base_corregida', 'devengo_id', v_linea.id,
                           'base_antes', v_neto_base, 'base_despues', v_base,
                           'moneda_antes', v_linea.moneda, 'moneda_despues', v_moneda, 'en', now())
      );
      update public.comision_admin_lineas set revisar = true, actualizado_en = now() where id = v_linea.id;

    else
      -- Ya facturada y lo que cambio es la moneda o la sociedad: no hay dinero
      -- nuevo que anotar, pero la factura emitida quedo apuntando a la PT o a la
      -- divisa equivocada. Eso lo arregla una persona, no el trigger.
      update public.comision_admin_lineas
         set revisar = true, actualizado_en = now(),
             nota = coalesce(nota || ' - ', '') ||
                    case when v_cambia_soc then 'El recibi cambio de sociedad (' ||
                           coalesce(v_linea.sociedad, '—') || ' -> ' || coalesce(new.sociedad, '—') ||
                           ') con la comision ya emitida. ' else '' end ||
                    case when v_cambia_mon then 'El recibi cambio de moneda (' ||
                           v_linea.moneda || ' -> ' || v_moneda ||
                           ') con la comision ya emitida. ' else '' end
       where id = v_linea.id;
    end if;
  end if;

  return new;
exception when others then
  raise warning 'comision_admin cambio (recibi %): %', new.id, sqlerrm;
  return new;
end;
$function$;

-- ── Borrado del recibi: la linea sobrevive y lo dice ─────────────────────────
create or replace function public._comision_admin_borrado_recibi()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_linea     record;
  v_neto_imp  numeric;
  v_neto_base numeric;
begin
  if coalesce(old.tipo, '') <> 'recibi' then
    return old;
  end if;

  select * into v_linea
    from public.comision_admin_lineas l
   where l.recibi_id = old.id and l.tipo_linea = 'devengo'
   limit 1;

  if v_linea.id is null then
    return old;
  end if;

  if not v_linea.anulada then
    select coalesce(sum(l.importe), 0), coalesce(sum(l.base_total), 0)
      into v_neto_imp, v_neto_base
      from public.comision_admin_lineas l
     where (l.id = v_linea.id or l.linea_origen_id = v_linea.id)
       and l.tipo_linea in ('devengo', 'ajuste');

    if v_neto_imp <> 0 or v_neto_base <> 0 then
      insert into public.comision_admin_lineas (
        tipo_linea, linea_origen_id, recibi_numero, sociedad, contrato_id, proyecto_id,
        devengado_el, fecha_recibi, base_total, moneda, pct_aplicado, importe,
        tarifa_id, estado, revisar, nota, snapshot
      ) values (
        'abono', v_linea.id, v_linea.recibi_numero, v_linea.sociedad,
        v_linea.contrato_id, v_linea.proyecto_id, current_date, v_linea.fecha_recibi,
        - v_neto_base, v_linea.moneda, v_linea.pct_aplicado, - v_neto_imp,
        v_linea.tarifa_id,
        case when v_linea.estado = 'exenta' then 'exenta' else 'pendiente' end,
        true,
        'Abono automatico: el recibi se BORRO de la base.',
        jsonb_build_object('motivo', 'recibi_borrado', 'devengo_id', v_linea.id,
                           'estado_al_borrar', v_linea.estado,
                           'neto_revertido', v_neto_imp, 'en', now())
      );
    end if;
  end if;

  -- [1] mismo acotado que en la rama (a): el abono recien creado no se anula
  update public.comision_admin_lineas
     set anulada = true, revisar = true, actualizado_en = now(),
         nota = coalesce(nota || ' - ', '') || 'El recibi ya no existe en la base.'
   where (id = v_linea.id or linea_origen_id = v_linea.id)
     and tipo_linea <> 'abono';

  return old;
exception when others then
  raise warning 'comision_admin borrado (recibi %): %', old.id, sqlerrm;
  return old;
end;
$function$;

-- ── Reponer un devengo de un recibi que se desanulo ──────────────────────────
-- [7] `anulada` no esta en el grant de UPDATE de `authenticated` a proposito
-- (el navegador no anula ni desanula lineas), asi que sin esto reponer un
-- devengo exigia SQL contra produccion. Con 10 de 97 recibis anulados, desanular
-- por error no es hipotetico.
create or replace function public.comision_admin_repone_devengo(p_linea_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_linea  record;
  v_recibi record;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_repone_devengo: solo super_admin';
  end if;

  select * into v_linea from public.comision_admin_lineas l
   where l.id = p_linea_id and l.tipo_linea = 'devengo';
  if v_linea.id is null then
    raise exception 'comision_admin_repone_devengo: no existe ese devengo';
  end if;
  if not v_linea.anulada then
    return jsonb_build_object('ok', false, 'motivo', 'el devengo no esta anulado');
  end if;

  select * into v_recibi from public.facturas f where f.id = v_linea.recibi_id;
  if v_recibi.id is null or coalesce(v_recibi.anulada, false) then
    raise exception 'comision_admin_repone_devengo: el recibi no existe o sigue anulado -- reponer el devengo dejaria el libro cobrando sobre dinero que no entro';
  end if;

  update public.comision_admin_lineas
     set anulada = false, revisar = true, actualizado_en = now(),
         nota = coalesce(nota || ' - ', '') || 'Devengo repuesto a mano por ' ||
                coalesce((select auth.email()), 'super_admin') || ' el ' || current_date || '.'
   where id = p_linea_id;

  return jsonb_build_object('ok', true, 'linea', p_linea_id, 'recibi', v_linea.recibi_numero);
end;
$function$;

revoke all on function public.comision_admin_repone_devengo(uuid) from public, anon, authenticated;
grant execute on function public.comision_admin_repone_devengo(uuid) to authenticated;

-- ── Reconciliacion: las tres rutas, y sin falsos positivos ───────────────────
create or replace function public.comision_admin_descuadres()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_desde date;
  v_sin_linea integer;
  v_mal_calculadas integer;
  v_sin_base integer;
  v_base_no_cuadra integer;
  v_anulado_vivo integer;
  v_vivo_anulado integer;
begin
  if not public.es_admin() then
    raise exception 'comision_admin_descuadres: solo administracion';
  end if;

  select min(efectivo_desde) into v_desde from public.comision_admin_tarifas;
  if v_desde is null then
    return jsonb_build_object('sin_tarifa', true);
  end if;

  select count(*) into v_sin_linea
    from public.facturas f
   where f.tipo = 'recibi'
     and not coalesce(f.anulada, false)
     and f.created_at::date >= v_desde
     and not exists (select 1 from public.comision_admin_lineas l
                      where l.recibi_id = f.id and l.tipo_linea = 'devengo');

  /* [6] SOLO devengos. En `ajuste` y `abono` el importe es una DIFERENCIA de
     redondeos, no `round(base*pct/100)`: con 0,5% y bases 101->202 el ajuste
     vale 0,50 y esta formula esperaria 0,51. Un banner rojo permanente que nadie
     puede limpiar se aprende a ignorar, y entonces deja de avisar de nada. */
  select count(*) into v_mal_calculadas
    from public.comision_admin_lineas l
   where l.tipo_linea = 'devengo'
     and l.importe is distinct from
         round(l.base_total * l.pct_aplicado / 100,
               case when upper(l.moneda) = 'IDR' then 0 else 2 end);

  select count(*) into v_sin_base
    from public.comision_admin_lineas l
   where l.tipo_linea = 'devengo' and l.base_total = 0 and not l.anulada;

  /* La base contra el RECIBI, no contra si misma: `importe` se recalcula DESDE
     `base_total`, asi que el contador de arriba cuadra siempre por construccion.
     El unico numero que el trigger no ha copiado de si mismo es el total del
     recibi menos su impuesto declarado. Si el jsonb `totales` deja de ser
     coherente con `total` --justo lo que pasaria al editar el subtotal a mano--
     salta aqui. */
  select count(*) into v_base_no_cuadra
    from public.comision_admin_lineas l
    join public.facturas f on f.id = l.recibi_id
   where l.tipo_linea = 'devengo'
     and not l.anulada
     and abs(coalesce(f.total, 0)
             - coalesce((f.datos -> 'totales' ->> 'impuesto')::numeric, 0)
             - l.base_total) > 0.01;

  /* Recibi anulado con su devengo vivo: lo que queda si el INSERT del abono se
     cayo dentro del `exception when others`. `recibis_sin_linea` no lo ve nunca,
     porque su filtro excluye los anulados. */
  select count(*) into v_anulado_vivo
    from public.facturas f
    join public.comision_admin_lineas l on l.recibi_id = f.id and l.tipo_linea = 'devengo'
   where f.tipo = 'recibi' and coalesce(f.anulada, false) and not l.anulada;

  /* Y el simetrico: recibi vivo con el devengo anulado — un recibi que se anulo
     y luego se desanulo. Se repone con comision_admin_repone_devengo(). */
  select count(*) into v_vivo_anulado
    from public.facturas f
    join public.comision_admin_lineas l on l.recibi_id = f.id and l.tipo_linea = 'devengo'
   where f.tipo = 'recibi' and not coalesce(f.anulada, false) and l.anulada;

  return jsonb_build_object(
    'desde', v_desde,
    'recibis_sin_linea', v_sin_linea,
    'lineas_mal_calculadas', v_mal_calculadas,
    'devengos_con_base_cero', v_sin_base,
    'devengos_con_base_distinta_del_recibi', v_base_no_cuadra,
    'anulados_con_devengo_vivo', v_anulado_vivo,
    'vivos_con_devengo_anulado', v_vivo_anulado,
    'para_revisar', (select count(*) from public.comision_admin_lineas where revisar)
  );
end;
$function$;

revoke all on function public._comision_admin_cambio_recibi()  from public, anon, authenticated;
revoke all on function public._comision_admin_borrado_recibi() from public, anon, authenticated;
revoke all on function public.comision_admin_descuadres()      from public, anon, authenticated;
grant execute on function public.comision_admin_descuadres() to authenticated;
