-- Comisiones desde el 1-nov-2026: 10 % de la parcela FIRMADA al cobrar el 50 % de la parcela + 10 % de la
-- construcción FIRMADA al cobrar el 25 % de la construcción (owner, 13-oct-2026, decisiones cerradas).
--
-- QUÉ CAMBIA
--  * Solo ventas con fecha de venta >= 2026-11-01 (la que ya usa el motor: coalesce(contrato_closer.fecha_venta,
--    created_at de la raíz en Asia/Makassar)). El corte lo hace la VIGENCIA de las condiciones: cada condición
--    genérica abierta con % > 0 se cierra el 31-oct y nace su sucesora desde el 1-nov (sustituye_a) con el mismo
--    nivel/equipo/empresa/proyecto/% y dos tramos. Las ventas anteriores siguen con su condición, sin cambio de importe.
--  * Base y disparo POR TRAMO: condicion_tramos.base_calculo (null = hereda la de la condición; todo lo existente
--    queda igual). Base efectiva = coalesce(tramo.base_calculo, condicion.base_calculo); importe fijo ignora el tramo.
--    Las sucesoras llevan base de condición 'por_tramo' (falla cerrado: un consumidor que no sepa de tramos calcula
--    null/0, nunca el 10 % del total) y cada tramo su base.
--  * Bases nuevas (fuente única: _comisiones_bases_firmadas):
--      precio_suelo_firmado = suma de precio_total de la familia (raíz + hijos) bloqueados, no liberados, que no son
--                             obra (contrato_tipo_etapa.es_obra, sin fila = no obra) ni carta (tipo like
--                             'carta_reserva%', raíz o hija: «la carta de reserva no devenga comisiones», owner).
--      precio_obra_firmada  = misma familia, bloqueados, no liberados, es_obra = true.
--    Invariante: parcela + obra <= _comisiones_precio_total(raíz) (esa excluye solo la carta hija; esta, toda carta).
--  * ADENDAS (decisión por defecto del CEO, 13-oct-2026, CAMBIADA tras la consulta de Administración): una adenda
--    (tipo like 'adenda%') con precio cuenta en la base de OBRA, nunca en la de parcela, aunque su contrato_tipo_etapa
--    diga es_obra = false (esa tabla no se toca: de ella sale v_obra_firmada y otras pantallas). Porqué: si contara en
--    la parcela, una adenda firmada después de disparar el tramo de parcela generaría al momento una DIF positiva y se
--    pagaría construcción por adelantado; en obra solo retrasa el pago al 25 % de obra. La clasificación vive en UN
--    sitio, _comisiones_parte_obra(tipo, es_obra), que usan las bases, la trazabilidad y la comprobación de
--    contracts/sql/comisiones_1nov_imputacion.sql. Hoy hay 0 contratos de tipo adenda (medido 13-oct).
--    No se excluyen: una adenda firmada con precio es «un cambio en el contrato» y tiene que mover la comisión.
--  * MONEDA (consulta de Administración, 13-oct-2026): bases y cobros se cuentan SOLO en la moneda de la raíz (un
--    contrato o un recibí en otra moneda no suma). Si la familia tiene contratos firmados (no liberados) en más de una
--    moneda, _comisiones_bases_firmadas lo marca (multimoneda) y el motor y el reconciliador NO tocan los tramos con base
--    o disparo «firmado» de esa raíz (raise warning con la raíz; el motor lo deja además en
--    comisiones_interruptor.ultimo_error, que ya vigila salud_lawang.py, y comisiones_1nov_imputacion.sql saca la fila). Medido 13-oct: 0 familias multimoneda, 0 recibís en moneda distinta de su contrato → no
--    cambia ningún número.
--  * Disparos nuevos pct_cobrado_suelo_firmado / pct_cobrado_obra_firmada: denominador = la base firmada de esa parte;
--    numerador = lo cobrado imputado con «PRIMERO PARCELA, LUEGO OBRA» (owner, 13-oct-2026, decisión cerrada, tras medir
--    que 9 de las 54 ventas firmadas tenían el cobro de la parcela en la carta y RP00047/RP00133 pasaban del 100 %):
--      bolsa   = cobrado en los contratos de parcela + cobrado en las cartas FIRMADAS no liberadas de la familia
--      parcela = least(parcela firmada, bolsa)
--      obra    = least(obra firmada, cobrado en obra + (bolsa - parcela))
--    Ninguna parte pasa del 100 %. La carta sigue sin sumar en ninguna BASE: solo su cobro cuenta como pago del cliente.
--    DESBORDE DE LA RP (decisión de Backend, coherente con la del owner; reversible quitando cp del sobrante): lo cobrado
--    en la RP por encima de su precio firmado desborda a obra igual que la carta (RP00047: la RP lleva 46.500 cobrados
--    sobre 20.000 de parcela y 26.500 de obra → 100 % / 100 %; sin desborde, la obra quedaba en 0 % con la casa pagada).
--    Lo cobrado en un contrato de OBRA no sube a la parcela (es dinero de obra; queda topado). SIN PARCELA FIRMADA no hay
--    desborde: la carta es la señal de una parcela que aún no existe y el devengo de obra no se podría deshacer al
--    firmarla (hoy: CR00021, CR00025, CR00038, CR00101, raíces carta sin hijos → nada hasta que se firme su RP;
--    medido 13-oct: las 25 cartas hijas se crearon ANTES que su padre, o sea, al hacer la RP la carta pasa a colgar de
--    ella, y el trigger zz_comisiones_reconcilia_cambio reevalúa la raíz al cambiar contrato_padre_id o bloqueado).
--    Medido 13-oct sobre las 54 ventas firmadas, como si la regla les aplicara (son todas anteriores al 1-nov: no
--    cambia ningún importe hoy): parcela ≥ 50 % pasa de 18 a 20 (RP00202, RP00124), obra ≥ 25 % de 2 a
--    4 (RP00047, RP00133), máximo 100,00 % en las dos partes. De las 9 con el cobro en la carta solo cruza RP00202
--    (99,8 %): RP00201/RP00077/RP00197/RP00132 tienen 1.000–5.000 en la carta (lejos del 50 %) y las 4 CR son raíces
--    carta sin parcela firmada. El cobrado en bruto (directo parcela, directo obra, cartas) va en el snapshot del
--    devengo para auditar la imputación. Los disparos viejos no cambian.
--    Carta liberada después de disparar: el reconciliador mueve importes por cambio de BASE y la carta no está en
--    ninguna; lo que cubre ese caso es la anulación del recibí (_comisiones_marca_disputa_por_recibi, trigger de
--    facturas). Medido 13-oct: las 5 cartas liberadas tienen 0 cobrado vivo (contrato_cobrado = 0).
--    DECISIONES POR DEFECTO de este bloque: desborde RP→obra, adendas en OBRA (ver ADENDAS), sin parcela firmada no hay
--    desborde, lo cobrado en obra no sube a parcela, carta liberada tras disparar solo la deshace anular el recibí.
--    ACEPTADO: CEO por defecto 13-oct-2026; el owner lo confirma en la ventana (fila L6 de para_el_owner_a_su_vuelta.md)
--    El cobro sale de _contrato_cobrado_interno: misma fórmula que contrato_cobrado SIN su puerta de rol (el motor es
--    interno; con la puerta, un recibí metido por un rol no agente dejaba el cobro en 0 sin avisar).
--    contrato_cobrado pasa a llamar a la interna: una sola fórmula. Con p_moneda (lo pasan las bases: la moneda de la
--    raíz) solo cuentan recibís y facturas en esa moneda; contrato_cobrado la llama sin moneda y no cambia.
--  * Motor (comisiones_evaluar_contrato): v_base se calcula DENTRO del bucle de tramos con la base efectiva; F8
--    (closer de equipo por plantilla) compara el CONJUNTO ordenado de bases efectivas distintas del manager y del closer
--    (con una sola base, o sin tramos, es exactamente la comparación viva de base de condición: un manager de 1 tramo y
--    un closer de 2 con la misma base siguen casando); snapshot y concepto llevan la base del tramo.
--  * comisiones_reconciliar: usa la base efectiva de CADA devengo (antes saltaba todo lo que no fuera precio_total
--    de la condición: con 'por_tramo' habría saltado, y con 'precio_total' habría pagado el 10 % del total).
--  * Edición de tramos (_condicion_tramos_pone, la que usa condicion_comision_guarda): acepta base_calculo por tramo;
--    si la clave falta (editor viejo) CONSERVA la base que había en ese orden. condicion_tramos_reemplaza NO se toca:
--    sin llamador desde el 27-sep, y quitarla es decisión del owner (erp/modulos.py); ver 6b.
--    _condicion_comision_guarda_en compara la base del tramo al decidir si «cambian las cifras». valida_suma_tramos_comision: 100 por base efectiva; 'por_tramo'
--    exige base en cada tramo; importe fijo no admite base de tramo; también al cambiar la base de la condición.
--  * Lecturas: condiciones_comision_datos, mi_condicion_comision (+ columna tramos), comision_trazabilidad (base del
--    tramo y «falta por firmar» por parte) y comision_de_solicitud_datos devuelven la base del tramo.
--  * Snapshot recortado en el SERVIDOR: comisiones_reparto_datos (la única RPC de authenticated que devuelve
--    disparado_por_snapshot; comision_trazabilidad no lo devuelve) quita las 7 cifras nuevas de la operación
--    (precio_*_firmad*, cobrado_*_firmad*, cobrado_directo_*, cobrado_cartas) a quien no tiene la vista completa, con
--    la MISMA regla que decide `completa` en comision_trazabilidad, ahora en un solo sitio: _comision_vista_completa.
--
-- REDEFINICIONES desde la definición VIVA del 13-oct-2026 (pg_get_functiondef), guardada como vuelta atrás en
-- supabase/vivo/20261013_comisiones_1nov/. Ninguna de las redefinidas es CRLF en la base. El bloque 0 para si
-- alguna cambió entre la foto y la aplicación (otra sesión parcheando el motor).
-- Sin dinero movido: lo devengado/aprobado/pagado no se toca (foto de comisiones_devengadas idéntica antes y después).
-- Prueba: contracts/sql/prueba_comisiones_1nov.sql (termina en excepción, no deja rastro ni consume series; casos C1–C5
-- para «primero parcela, luego obra») y contracts/sql/comisiones_1nov_imputacion.sql (solo lectura: la función real
-- contra la regla calculada a mano en las 54 ventas firmadas; filas solo si algo está mal).
--
-- destructivo-ok: (necesita además la marca del owner ~/.axisworks/destructivo-ok; tools/no_destruir.py). Lo único que
-- la válvula abre aquí, y nada más: (1b) se quitan y reponen AMPLIADOS tres CHECK —condiciones_comision.base_calculo,
-- condicion_tramos.disparador_tipo y condicion_tramos_umbral_coherente— con la lista vieja más los valores nuevos;
-- (6) _condicion_tramos_pone se redefine y su cuerpo conserva el DELETE de los tramos que ya traía (borra y repone los
-- tramos de UNA condición);
-- (10b) mi_condicion_comision se quita y se crea para añadirle la columna tramos. Ningún dato se borra ni se sobrescribe.

-- 0 · guarda: las funciones a redefinir son las que se fotografiaron (solo en la primera aplicación)
do $$
declare v record;
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'condicion_tramos' and column_name = 'base_calculo') then
    return;   -- ya aplicada: el resto es idempotente
  end if;
  for v in select * from (values
      ('public.comisiones_evaluar_contrato(uuid)', '3ae27316aba2045428d5a763981c3f01'),
      ('public.comisiones_reconciliar(uuid,boolean,jsonb)', '4d2bff43e2f47834e9a6c30334e6f3c7'),
      ('public._condicion_tramos_pone(uuid,jsonb)', '1e0dfd064a1dc32955ab69e056ec1ec5'),
      ('public.valida_suma_tramos_comision()', '11a246607c2097424f10dc6a140bbed1'),
      ('public.condiciones_comision_datos()', 'c74355e79665c6dbada4b327d0c6156a'),
      ('public.mi_condicion_comision()', '07575d8e7d35e0f1902ee22374978441'),
      ('public.comision_trazabilidad(uuid)', 'ff6399cf578171a83ca5ce5ee996843d'),
      ('public.comision_de_solicitud_datos(uuid)', '2a36889bfefc2cd46f2cd68907d84a43'),
      ('public.contrato_cobrado(uuid)', '644391725cb6a32f4ca6450f09b8abd7'),
      ('public.comisiones_reparto_datos()', 'd7eb53f49eeb6ecc3ce425c9f49c2a2a'),
      ('public._condicion_comision_guarda_en(uuid,jsonb,jsonb,text,text)', '283a288773288a67e26215a7a9c8dbb7')
    ) x(f, h)
  loop
    if md5(pg_get_functiondef(v.f::regprocedure)) <> v.h then
      raise exception 'comisiones 1-nov: % ha cambiado desde la foto del 13-oct; rehacer la migración sobre la viva', v.f;
    end if;
  end loop;
end $$;

-- 1 · esquema: base por tramo (columna nueva con su CHECK en línea: no hace falta la válvula)
alter table public.condicion_tramos add column if not exists base_calculo text
  constraint condicion_tramos_base_calculo_check check (
    base_calculo is null or base_calculo = any (array['precio_total', 'precio_suelo', 'precio_construccion',
                                                      'precio_suelo_firmado', 'precio_obra_firmada']));
comment on column public.condicion_tramos.base_calculo is
  'Base de cálculo del tramo (13-oct-2026). null = hereda la de la condición. Base efectiva = coalesce(tramo, condición); con importe_fijo no aplica.';

-- 1b · CHECKs ampliados (VÁLVULA: se quita cada CHECK y se pone otro con la lista vieja + los valores nuevos;
--      ninguna fila existente deja de cumplirlo)
alter table public.condiciones_comision drop constraint if exists condiciones_comision_base_calculo_check;
alter table public.condiciones_comision add constraint condiciones_comision_base_calculo_check check (
  base_calculo = any (array['precio_total', 'precio_suelo', 'precio_construccion', 'importe_fijo',
                            'precio_suelo_firmado', 'precio_obra_firmada', 'por_tramo']));

alter table public.condicion_tramos drop constraint if exists condicion_tramos_disparador_tipo_check;
alter table public.condicion_tramos add constraint condicion_tramos_disparador_tipo_check check (
  disparador_tipo = any (array['pct_cobrado_suelo', 'pct_cobrado_obra', 'pct_cobrado_total', 'obra_firmada',
                               'contrato_firmado', 'pct_cobrado_suelo_firmado', 'pct_cobrado_obra_firmada']));

alter table public.condicion_tramos drop constraint if exists condicion_tramos_umbral_coherente;
alter table public.condicion_tramos add constraint condicion_tramos_umbral_coherente check (
  (disparador_tipo = any (array['obra_firmada', 'contrato_firmado']) and umbral is null)
  or (disparador_tipo = any (array['pct_cobrado_suelo', 'pct_cobrado_obra', 'pct_cobrado_total',
                                   'pct_cobrado_suelo_firmado', 'pct_cobrado_obra_firmada'])
      and umbral is not null and umbral >= 0 and umbral <= 100));

-- 2 · cobrado de un contrato: una sola fórmula, con y sin puerta de rol
create or replace function public._contrato_cobrado_interno(p_contrato_id uuid, p_moneda text default null)
 returns numeric
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- Fórmula única del cobrado de un contrato (13-oct-2026). contrato_cobrado() la llama tras su puerta de rol y SIN
  -- moneda (no cambia nada); las bases de comisión la llaman con la moneda de la raíz: un recibí (o la factura a la que
  -- se aplica) en otra moneda no suma (consulta de Administración, 13-oct-2026; medido: 0 casos hoy).
  select coalesce((
      select sum(ra.importe_aplicado)
        from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
        join public.facturas f on f.id = ra.factura_id
       where f.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not coalesce(f.anulada, false)
         and (p_moneda is null or (r.moneda is not distinct from p_moneda and f.moneda is not distinct from p_moneda))
    ), 0)
    + coalesce((
      select sum(
        r.total - coalesce((
          select sum(ra.importe_aplicado)
            from public.recibi_aplicaciones ra
            join public.facturas f2 on f2.id = ra.factura_id
           where ra.recibi_id = r.id
             and f2.contrato_id is not null
             and not coalesce(f2.anulada, false)
        ), 0))
        from public.facturas r
       where r.tipo = 'recibi'
         and r.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and (p_moneda is null or r.moneda is not distinct from p_moneda)
    ), 0);
$function$;

create or replace function public.contrato_cobrado(p_contrato_id uuid)
 returns numeric
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_existe boolean;
begin
  select true into v_existe from public.contratos c where c.id = p_contrato_id;
  if not coalesce(v_existe, false) then return 0; end if;
  if (select auth.role()) <> 'service_role'
     and not (public.es_agente() or public.es_portal()) then
    return 0;
  end if;
  return public._contrato_cobrado_interno(p_contrato_id);
end;
$function$;

-- 3 · bases firmadas (fuente única de las dos bases nuevas y de su % cobrado)
-- 3a · de qué parte es un contrato para la comisión (UN sitio: bases, trazabilidad y comisiones_1nov_imputacion.sql).
--      Obra = su tipo es de obra en contrato_tipo_etapa, o es una ADENDA (decisión por defecto del CEO, 13-oct-2026:
--      en parcela, una adenda firmada tras disparar la parcela pagaría construcción por adelantado; en obra solo retrasa).
create or replace function public._comisiones_parte_obra(p_tipo text, p_es_obra boolean)
 returns boolean
 language sql
 immutable
 set search_path to ''
as $function$
  select coalesce(p_es_obra, false) or coalesce(p_tipo, '') like 'adenda%';
$function$;

create or replace function public._comisiones_bases_firmadas(p_raiz uuid)
 returns table(suelo_firmado numeric, obra_firmada numeric, cobrado_suelo_firmado numeric, cobrado_obra_firmada numeric,
               cobrado_directo_suelo numeric, cobrado_directo_obra numeric, cobrado_cartas numeric, multimoneda boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- Regla del owner del 13-oct-2026 (ventas desde el 1-nov). Conjunto = familia de la raíz (raíz + hijos)
  -- firmados (bloqueados) y no liberados. Parte = contrato_tipo_etapa.es_obra (tipo sin fila = no obra).
  -- BASES: las cartas de reserva (raíz o hija) no suman en ninguna («la carta no devenga comisiones»).
  -- COBRADO, «primero parcela, luego obra» (owner, 13-oct-2026, decisión cerrada):
  --   bolsa      = cobrado en los contratos de parcela + cobrado en las cartas firmadas de la familia
  --   parcela    = least(precio parcela firmada, bolsa)                      -- nunca > 100 %
  --   obra       = least(precio obra firmada, cobrado en obra + (bolsa - parcela))   -- nunca > 100 %
  --   * Lo cobrado en la carta es pago del cliente: completa primero la parcela firmada y el sobrante va a obra.
  --   * Lo cobrado en la propia RP por encima de su precio firmado (RP00047: la RP lleva el precio de la parcela
  --     y el de la casa) es el mismo dinero sin parte asignada: desborda a obra con la misma regla.
  --   * Lo cobrado en un contrato de obra es de obra: su exceso no sube a la parcela (queda topado).
  --   * Sin parcela firmada (precio 0) no hay desborde: la carta es la señal de una parcela que aún no existe, y si
  --     el sobrante disparara la obra, al firmarse la RP ese dinero volvería a la parcela con el devengo de obra ya
  --     pagado (no se puede deshacer). Ese dinero cuenta en cuanto se firma la parcela.
  -- Columnas 5–7: el cobrado en bruto (para el snapshot y la trazabilidad: auditar la imputación).
  -- MONEDA (13-oct-2026): solo cuentan contratos y cobros en la moneda de la raíz; multimoneda = la familia tiene algún
  -- contrato firmado no liberado en otra moneda (el motor y el reconciliador no tocan entonces los tramos «firmados»).
  -- PARTE: _comisiones_parte_obra (adenda = obra).
  with r as (
    select c.moneda from public.contratos c where c.id = p_raiz
  ), fam as (
    select c.id, c.tipo, c.moneda, c.precio_total
      from public.contratos c
     where (c.id = p_raiz or c.contrato_padre_id = p_raiz)
       and coalesce(c.bloqueado, false)
       and c.liberado_en is null
  ), x as (
    select f.id, coalesce(f.precio_total, 0) as precio, public._comisiones_parte_obra(f.tipo, e.es_obra) as es_obra,
           coalesce(f.tipo, '') like 'carta_reserva%' as es_carta
      from fam f
      left join public.contrato_tipo_etapa e on e.tipo = f.tipo
     where f.moneda is not distinct from (select r.moneda from r)
  ), y as (
    select x.precio, x.es_obra, x.es_carta, public._contrato_cobrado_interno(x.id, (select r.moneda from r)) as cobrado from x
  ), s as (
    select coalesce(sum(y.precio)  filter (where not y.es_carta and not y.es_obra), 0) as p,
           coalesce(sum(y.precio)  filter (where not y.es_carta and y.es_obra), 0)     as o,
           coalesce(sum(y.cobrado) filter (where not y.es_carta and not y.es_obra), 0) as cp,
           coalesce(sum(y.cobrado) filter (where not y.es_carta and y.es_obra), 0)     as co,
           coalesce(sum(y.cobrado) filter (where y.es_carta), 0)                       as cc
      from y
  ), i as (
    select s.*, case when s.p > 0 then greatest(least(s.p, s.cp + s.cc), 0) else 0 end as ip from s
  )
  select i.p, i.o, i.ip,
         greatest(least(i.o, i.co + case when i.p > 0 then greatest(i.cp + i.cc - i.ip, 0) else 0 end), 0),
         i.cp, i.co, i.cc,
         exists (select 1 from fam f where f.moneda is distinct from (select r.moneda from r))
    from i;
$function$;

-- 4 · resumen de tramos con su base efectiva (lo leen mi_condicion_comision y el editor)
create or replace function public._condicion_tramos_resumen(p_condicion uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'orden', t.orden, 'disparador_tipo', t.disparador_tipo, 'umbral', t.umbral, 'pct_tramo', t.pct_tramo,
           'base_calculo', t.base_calculo,
           'base_efectiva', case when c.base_calculo = 'importe_fijo' then 'importe_fijo'
                                 else coalesce(t.base_calculo, c.base_calculo) end)
           order by t.orden), '[]'::jsonb)
    from public.condicion_tramos t
    join public.condiciones_comision c on c.id = t.condicion_id
   where t.condicion_id = p_condicion;
$function$;

revoke all on function public._contrato_cobrado_interno(uuid, text) from public, anon, authenticated;
revoke all on function public._comisiones_parte_obra(text, boolean) from public, anon, authenticated;
revoke all on function public._comisiones_bases_firmadas(uuid) from public, anon, authenticated;
revoke all on function public._condicion_tramos_resumen(uuid) from public, anon, authenticated;
grant execute on function public._contrato_cobrado_interno(uuid, text) to service_role;
grant execute on function public._comisiones_parte_obra(text, boolean) to service_role;
grant execute on function public._comisiones_bases_firmadas(uuid) to service_role;
grant execute on function public._condicion_tramos_resumen(uuid) to service_role;

-- 5 · validación de tramos: 100 por base efectiva
create or replace function public.valida_suma_tramos_comision()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_condicion_id uuid;
  v_base_cond    text;
  v_n            integer;
  v_suma         numeric;
  v_mal          text;
  v_nbases       integer;
begin
  -- Se dispara desde condicion_tramos (alta/cambio/baja de un tramo) y desde condiciones_comision (cambio de su
  -- base_calculo, 13-oct-2026). Cada rama lee su propia columna: la otra no existe en esa fila.
  if tg_table_name = 'condiciones_comision' then
    v_condicion_id := new.id;
  else
    v_condicion_id := coalesce(new.condicion_id, old.condicion_id);
  end if;

  -- La condición padre ya no existe (se borró ella misma, arrastrando estos
  -- tramos por el ON DELETE CASCADE): nada que validar, no queda condición
  -- viva con un % a medias.
  select c.base_calculo into v_base_cond from public.condiciones_comision c where c.id = v_condicion_id;
  if not found then
    return coalesce(new, old);
  end if;

  select count(*), coalesce(sum(pct_tramo), 0) into v_n, v_suma
    from public.condicion_tramos
   where condicion_id = v_condicion_id;

  -- una condición sin tramos solo se valida desde sus tramos (las de 0 % por closer no llevan tramos)
  if tg_table_name = 'condiciones_comision' and v_n = 0 then
    return new;
  end if;

  if v_base_cond = 'importe_fijo' and exists (select 1 from public.condicion_tramos t
                                               where t.condicion_id = v_condicion_id and t.base_calculo is not null) then
    raise exception 'la condición % es de importe fijo: sus tramos no llevan base de cálculo', v_condicion_id
      using errcode = '23514';
  end if;
  if v_base_cond = 'por_tramo' and exists (select 1 from public.condicion_tramos t
                                            where t.condicion_id = v_condicion_id and t.base_calculo is null) then
    raise exception 'la condición % calcula por tramo: cada tramo necesita su base de cálculo', v_condicion_id
      using errcode = '23514';
  end if;

  select count(*), string_agg(x.b || ' suman ' || x.s, ', ' order by x.b) filter (where abs(x.s - 100) > 0.01)
    into v_nbases, v_mal
    from (select coalesce(t.base_calculo, v_base_cond) as b, sum(t.pct_tramo) as s
            from public.condicion_tramos t where t.condicion_id = v_condicion_id group by 1) x;

  if v_n = 0 or (v_nbases = 1 and v_mal is not null) then
    raise exception 'los tramos de la condición % suman % (deben sumar exactamente 100)',
      v_condicion_id, v_suma using errcode = '23514';
  end if;
  if v_mal is not null then
    raise exception 'los tramos de la condición % deben sumar 100 en cada base de cálculo: %', v_condicion_id, v_mal
      using errcode = '23514';
  end if;

  return coalesce(new, old);
end;
$function$;

do $$
begin
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.condiciones_comision'::regclass and tgname = 'condiciones_comision_tramos_suma') then
    create constraint trigger condiciones_comision_tramos_suma
      after update of base_calculo on public.condiciones_comision
      deferrable initially deferred
      for each row when (old.base_calculo is distinct from new.base_calculo)
      execute function public.valida_suma_tramos_comision();
  end if;
end $$;

-- 6 · edición de tramos (VÁLVULA: sus cuerpos ya traían el DELETE de los tramos que se reponen; no cambia): base por tramo; si la clave falta, se conserva la del mismo orden
create or replace function public._condicion_tramos_pone(p_condicion uuid, p_tramos jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_viejas jsonb;
begin
  if p_tramos is null or jsonb_typeof(p_tramos) <> 'array' or jsonb_array_length(p_tramos) = 0 then
    raise exception 'Hacen falta tramos de pago' using errcode = '23514';
  end if;
  -- 13-oct-2026: base por tramo. Un editor que no la manda (clave ausente) conserva la que había en ese orden;
  -- base_calculo null o '' explícito = hereda la de la condición.
  select coalesce(jsonb_object_agg(t.orden::text, t.base_calculo), '{}'::jsonb) into v_viejas
    from public.condicion_tramos t where t.condicion_id = p_condicion;
  delete from public.condicion_tramos where condicion_id = p_condicion;
  insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo, base_calculo)
  select p_condicion, ord, t->>'disparador_tipo',
         case when (t->>'disparador_tipo') like 'pct_cobrado_%' then (t->>'umbral')::numeric end,
         (t->>'pct_tramo')::numeric,
         case when t ? 'base_calculo' then nullif(btrim(t->>'base_calculo'), '') else v_viejas->>(ord::text) end
    from jsonb_array_elements(p_tramos) with ordinality as x(t, ord);
end $function$;

-- 6b · condicion_tramos_reemplaza NO se toca (CEO, 13-oct-2026): sin llamador desde el 27-sep (solo EXECUTE de postgres
--      y service_role), y borrarla es «decisión del owner» según erp/modulos.py (catálogo de funciones). Ni se amplía ni
--      se quita: si alguien la llamara, sus tramos nacen sin base (null = heredan la de la condición), como hoy.

-- 7 · guarda de la condición: «cambian las cifras» mira también la base del tramo (parche por marca de UNA línea
--     sobre la viva: la función es de 17 KB y solo cambian dos líneas)
do $$
declare
  v_def text := pg_get_functiondef('public._condicion_comision_guarda_en(uuid,jsonb,jsonb,text,text)'::regprocedure);
  m1 text := $m$  select coalesce(jsonb_agg(jsonb_build_array(t.disparador_tipo, t.umbral, t.pct_tramo) order by t.orden), '[]'::jsonb)$m$;
  n1 text := $m$  select coalesce(jsonb_agg(jsonb_build_array(t.disparador_tipo, t.umbral, t.pct_tramo, t.base_calculo) order by t.orden), '[]'::jsonb)$m$;
  m2 text := $m$               (x->>'pct_tramo')::numeric) order by o), '[]'::jsonb)$m$;
  n2 text := $m$               (x->>'pct_tramo')::numeric, case when x ? 'base_calculo' then nullif(btrim(x->>'base_calculo'), '') else (select t0.base_calculo from public.condicion_tramos t0 where t0.condicion_id = p_id and t0.orden = o) end) order by o), '[]'::jsonb)$m$;
begin
  if position(n1 in v_def) > 0 and position('t0.base_calculo' in v_def) > 0 then
    return;   -- ya aplicado
  end if;
  if (length(v_def) - length(replace(v_def, m1, ''))) / length(m1) <> 1
     or (length(v_def) - length(replace(v_def, m2, ''))) / length(m2) <> 1 then
    raise exception 'comisiones 1-nov: las marcas de _condicion_comision_guarda_en no aparecen una sola vez';
  end if;
  execute replace(replace(v_def, m1, n1), m2, n2);
end $$;

-- 8 · motor (definición viva del 13-oct + base por tramo, bases firmadas y F8 por tramos)
create or replace function public.comisiones_evaluar_contrato(p_contrato_id uuid)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_raiz_id              uuid;
  v_raiz_creada          date;
  v_fecha_equipo         date;
  v_moneda               text;
  v_proyecto_id          uuid;
  v_contrato_firmado     boolean := false;
  v_obra_firmada         boolean := false;
  v_precio_total         numeric := 0;
  v_precio_suelo         numeric := 0;
  v_precio_construccion  numeric := 0;
  v_cobrado_suelo        numeric := 0;
  v_cobrado_obra         numeric := 0;
  v_cobrado_total        numeric := 0;
  v_suelo_firm           numeric := 0;
  v_obra_firm            numeric := 0;
  v_cob_suelo_firm       numeric := 0;
  v_cob_obra_firm        numeric := 0;
  v_cob_dir_suelo        numeric := 0;   -- cobrado en bruto (auditoría de «primero parcela, luego obra»)
  v_cob_dir_obra         numeric := 0;
  v_cob_cartas           numeric := 0;
  v_multimoneda          boolean := false;
  v_mm_avisado           boolean := false;
  v_closer_email         text;
  v_fecha_venta          date;
  v_equipo_id            uuid;
  v_manager_email        text;
  v_propia               public.reclamaciones_venta_propia;
  v_niveles              text[];
  v_ultimo_recibi_id     uuid;
  v_ultimo_recibi_en     timestamptz;
  v_nivel                text;
  v_beneficiario         text;
  v_condicion            record;
  v_cond_fija            uuid;
  v_prev                 public.comisiones_devengadas;
  v_snap                 jsonb;
  v_tramo                record;
  v_base                 numeric;
  v_base_ef              text;
  v_importe              numeric;
  v_devengo_id           uuid;
  v_sp_id                uuid;
  v_creado_por           uuid;
  v_concepto             text;
  v_creados              integer := 0;
  v_eq_cong              uuid;
  v_man_cong             text;
  v_congelado            boolean := false;
  v_modo                 text;
  v_espera               timestamptz;
  v_propia_modo          boolean := false;
  v_pct_efectivo         numeric;
  v_plt_pct              numeric;
  v_plt_n                integer;
  v_prev_snap            jsonb;
  v_man_id               uuid;
  v_man_pct              numeric;
  v_man_base             text;
  v_man_bases            text[];
  v_clo_bases            text[];
  v_empresa              text;
begin
  if p_contrato_id is null then
    return 0;
  end if;

  select coalesce(c.contrato_padre_id, c.id) into v_raiz_id
    from public.contratos c
   where c.id = p_contrato_id;

  if v_raiz_id is null then
    return 0;
  end if;

  perform pg_advisory_xact_lock(hashtext('comisiones:' || v_raiz_id::text));

  select c.moneda, c.proyecto_id, c.bloqueado, (c.created_at at time zone 'Asia/Makassar')::date
    into v_moneda, v_proyecto_id, v_contrato_firmado, v_raiz_creada
    from public.contratos c
   where c.id = v_raiz_id;

  v_precio_total := public._comisiones_precio_total(v_raiz_id);
  v_empresa := public._empresa_de_proyecto_int(v_proyecto_id);

  v_obra_firmada := exists (
    select 1 from public.contratos h
     where h.contrato_padre_id = v_raiz_id and h.bloqueado and exists (select 1 from public.contrato_tipo_etapa e where e.tipo = h.tipo and e.es_obra)
  );

  select coalesce(sum(u.precio_suelo), 0),
         coalesce(sum(u.precio_construccion), 0),
         coalesce(sum(cp.cobrado_suelo), 0),
         coalesce(sum(cp.cobrado_obra), 0)
    into v_precio_suelo, v_precio_construccion, v_cobrado_suelo, v_cobrado_obra
    from public.unidades u
    left join lateral public.unidad_parte_cobrada_interno(u.id) cp on true
   where u.contrato_id = v_raiz_id;

  v_cobrado_total := v_cobrado_suelo + v_cobrado_obra;

  -- 13-oct-2026: bases firmadas por parte (parcela / construcción) y su % cobrado sobre el mismo conjunto
  select b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
         b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas, b.multimoneda
    into v_suelo_firm, v_obra_firm, v_cob_suelo_firm, v_cob_obra_firm,
         v_cob_dir_suelo, v_cob_dir_obra, v_cob_cartas, v_multimoneda
    from public._comisiones_bases_firmadas(v_raiz_id) b;
  v_multimoneda := coalesce(v_multimoneda, false);

  select k.closer_email, k.fecha_venta into v_closer_email, v_fecha_venta
    from public.contrato_closer k
   where k.contrato_id = v_raiz_id;

  if v_closer_email is null then
    return 0;
  end if;

  v_raiz_creada := coalesce(v_fecha_venta, v_raiz_creada);
  v_fecha_equipo := v_raiz_creada;

  select k.equipo_id, k.manager_email, (k.equipo_congelado_en is not null), k.modo, k.modo_espera_hasta
    into v_eq_cong, v_man_cong, v_congelado, v_modo, v_espera
    from public.contrato_closer k where k.contrato_id = v_raiz_id;
  if coalesce(v_congelado, false) then
    v_equipo_id := v_eq_cong;
  else
  select em.equipo_id into v_equipo_id
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id
   where lower(em.closer_email) = lower(v_closer_email)
     and ev.empresa = v_empresa
     and ev.activo
     and em.desde <= v_fecha_equipo
     and (em.hasta is null or em.hasta >= v_fecha_equipo)
   order by em.created_at desc
   limit 1;
  end if;

  if v_proyecto_id is null or v_moneda is null then
    return 0;
  end if;

  if v_modo is null then
    select * into v_propia
      from public.reclamaciones_venta_propia r
     where r.contrato_raiz_id = v_raiz_id and r.estado = 'aprobada' and r.tipo = 'reclamacion';
  end if;

  if v_modo = 'propia' and v_equipo_id is not null then
    if (v_espera is not null and v_espera > now())
       or exists (select 1 from public.reclamaciones_venta_propia r
                   where r.contrato_raiz_id = v_raiz_id and r.tipo = 'objecion' and r.estado = 'pendiente') then
      return 0;
    end if;
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_propia_modo := true;
    v_niveles := array['propia'];
  elsif v_modo = 'propia' then
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  elsif v_propia.id is not null then
    if lower(v_propia.solicitante_email) <> lower(v_closer_email) then
      return 0;
    end if;
    v_equipo_id := v_propia.equipo_id;
    v_niveles := array['propia'];
  elsif v_equipo_id is not null then
    if coalesce(v_congelado, false) then
      v_manager_email := v_man_cong;
    else
      select ev.manager_email into v_manager_email from public.equipos_venta ev where ev.id = v_equipo_id;
    end if;
    v_niveles := array['manager', 'closer', 'setter', 'team_lead'];
  else
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  end if;

  select r.id, r.created_at
    into v_ultimo_recibi_id, v_ultimo_recibi_en
    from public.facturas r
   where r.tipo = 'recibi'
     and not coalesce(r.anulada, false)
     and (
       r.contrato_id = v_raiz_id
       or r.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id)
       or exists (
            select 1
              from public.recibi_aplicaciones ra
              join public.facturas f on f.id = ra.factura_id
             where ra.recibi_id = r.id
               and not coalesce(f.anulada, false)
               and (f.contrato_id = v_raiz_id
                    or f.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id))
          )
     )
   order by r.created_at desc
   limit 1;

  if v_ultimo_recibi_id is null then
    return 0;
  end if;

  foreach v_nivel in array v_niveles
  loop
    v_beneficiario := null;
    v_pct_efectivo := null;
    v_plt_pct := null;

    if v_nivel in ('closer', 'setter', 'team_lead') then
      if v_nivel = 'closer' then
        v_beneficiario := v_closer_email;
      else
        select re.email into v_beneficiario
          from public.contrato_roles_equipo re
         where re.contrato_raiz_id = v_raiz_id and re.rol = v_nivel and re.equipo_id = v_equipo_id;
      end if;
      if v_beneficiario is null then
        continue;
      end if;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and lower(c.closer_email) = lower(v_beneficiario)
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

      if not found then
        select * into v_condicion
          from public.condiciones_comision c
         where c.equipo_id = v_equipo_id
           and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_raiz_creada
           and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;

    elsif v_nivel = 'estandar' or (v_nivel = 'propia' and v_propia_modo) then
      v_beneficiario := v_closer_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id is null
         and c.empresa = v_empresa
         and c.nivel = 'closer'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = lower(v_closer_email))
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

    else
      v_beneficiario := case when v_nivel = 'propia' then v_closer_email else v_manager_email end;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = 'manager'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and c.closer_email is null
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
    end if;

    v_cond_fija := null;
    if v_beneficiario is not null then
      select d.condicion_id into v_cond_fija
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and lower(d.beneficiario_email) = lower(v_beneficiario)
         and d.nivel = v_nivel
       order by d.created_at, d.id
       limit 1;
      if v_cond_fija is not null then
        select * into v_condicion from public.condiciones_comision c where c.id = v_cond_fija;
      end if;
    end if;

    if v_condicion.id is null or v_beneficiario is null then
      continue;
    end if;

    if v_condicion.base_calculo <> 'importe_fijo' and v_condicion.pct_comision = 0 then
      continue;
    end if;

    -- F8: el devengo del closer de equipo sale de la plantilla del SM (% del bote del manager), no de una cifra suelta.
    -- Solo la condicion generica del equipo (closer_email null): una por closer (p. ej. 0 % propio) sigue mandando.
    if v_nivel = 'closer' and v_equipo_id is not null and v_condicion.equipo_id = v_equipo_id
       and v_condicion.closer_email is null and v_condicion.base_calculo <> 'importe_fijo' then
      select d.disparado_por_snapshot into v_prev_snap
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.nivel = 'closer'
         and lower(d.beneficiario_email) = lower(v_beneficiario)
       order by d.created_at, d.id
       limit 1;
      if found then
        -- ya hay primer devengo: se relee SU congelado (sin plantilla_pct = la plantilla no aplica en esta raiz)
        v_plt_pct := nullif(v_prev_snap->>'plantilla_pct', '')::numeric;
      else
        select count(*), max(p.pct) into v_plt_n, v_plt_pct
          from public.plantilla_reparto p
         where p.equipo_id = v_equipo_id and p.rol_tipo = 'closer';
        if v_plt_n <> 1 then
          if v_plt_n > 1 then
            raise warning 'comisiones_evaluar_contrato: el equipo % tiene % filas closer en su plantilla; se usa la condicion de closer (raiz %)', v_equipo_id, v_plt_n, v_raiz_id;
          end if;
          v_plt_pct := null;
        end if;
      end if;

      if v_plt_pct is not null then
        -- la condicion manager con la que la venta devengo (fija) o, si aun no hay, la vigente
        select d.condicion_id into v_man_id
          from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id and d.nivel = 'manager'
         order by d.created_at, d.id
         limit 1;
        if v_man_id is null then
          select c.id into v_man_id
            from public.condiciones_comision c
           where c.equipo_id = v_equipo_id
             and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
             and c.nivel = 'manager'
             and (c.activo or c.vigente_hasta is not null)
             and c.vigente_desde <= v_raiz_creada
             and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
             and c.closer_email is null
           order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
           limit 1;
        end if;
        select c.pct_comision, c.base_calculo into v_man_pct, v_man_base
          from public.condiciones_comision c where c.id = v_man_id;
        -- 13-oct-2026: se compara el CONJUNTO ordenado de bases efectivas distintas (no tramo a tramo: un manager de 1
        -- tramo y un closer de 2 con la misma base casaban antes y siguen casando). Sin tramos o con todas heredadas es
        -- {base de la condición}: exactamente la comparación viva. Importe fijo nunca casa con un % (como antes).
        select coalesce(array_agg(distinct x.b order by x.b), array[v_man_base])
          into v_man_bases
          from (select case when v_man_base = 'importe_fijo' then 'importe_fijo'
                            else coalesce(t.base_calculo, v_man_base) end as b
                  from public.condicion_tramos t where t.condicion_id = v_man_id) x;
        select coalesce(array_agg(distinct x.b order by x.b), array[v_condicion.base_calculo])
          into v_clo_bases
          from (select coalesce(t.base_calculo, v_condicion.base_calculo) as b
                  from public.condicion_tramos t where t.condicion_id = v_condicion.id) x;
        if v_man_pct is null or v_man_bases is distinct from v_clo_bases then
          raise warning 'comisiones_evaluar_contrato: la condicion manager del equipo % no casa con la de closer (base o falta); se usa la condicion de closer (raiz %)', v_equipo_id, v_raiz_id;
          v_plt_pct := null;
        else
          v_pct_efectivo := least(v_plt_pct, 100) / 100 * v_man_pct;
        end if;
      end if;
    end if;

    for v_tramo in
      select * from public.condicion_tramos
       where condicion_id = v_condicion.id
       order by orden
    loop
      -- 13-oct-2026: base efectiva del TRAMO (null = la de la condición); importe fijo no usa base
      v_base_ef := case when v_condicion.base_calculo = 'importe_fijo' then 'importe_fijo'
                        else coalesce(v_tramo.base_calculo, v_condicion.base_calculo) end;
      v_base := case v_base_ef
        when 'precio_total'         then v_precio_total
        when 'precio_suelo'         then v_precio_suelo
        when 'precio_construccion'  then v_precio_construccion
        when 'precio_suelo_firmado' then v_suelo_firm
        when 'precio_obra_firmada'  then v_obra_firm
        else null
      end;

      -- 13-oct-2026 (Administración): familia con contratos firmados en más de una moneda → ningún tramo «firmado»
      -- (base o disparo) devenga hasta que se resuelva; el aviso lleva la raíz
      if v_multimoneda and (v_base_ef in ('precio_suelo_firmado', 'precio_obra_firmada')
                            or v_tramo.disparador_tipo in ('pct_cobrado_suelo_firmado', 'pct_cobrado_obra_firmada')) then
        raise warning 'comisiones_evaluar_contrato: la venta (raiz %) tiene contratos firmados en mas de una moneda; el tramo % de la condicion % no devenga', v_raiz_id, v_tramo.orden, v_condicion.id;
        -- y queda donde ya mira salud_lawang.py («ningun recalculo de comisiones ha fallado en silencio»): un warning
        -- solo llega al log de Postgres
        if not v_mm_avisado then
          update public.comisiones_interruptor
             set ultimo_error = 'venta en mas de una moneda: sus tramos de parcela/obra firmada no devengan (raiz ' || v_raiz_id || ')',
                 ultimo_error_en = now()
           where id;
          v_mm_avisado := true;
        end if;
        continue;
      end if;

      v_prev := null;
      select * into v_prev
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.tramo_id = v_tramo.id
         and d.beneficiario_email = v_beneficiario;
      if v_prev.id is not null and (v_prev.estado <> 'anulada' or not v_prev.anulado_por_modo) then
        continue;
      end if;

      if v_nivel in ('manager', 'estandar', 'propia') and exists (
        select 1 from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id
           and d.tramo_id = v_tramo.id
           and d.nivel in ('manager', 'estandar', 'propia')
           and d.estado <> 'anulada'
      ) then
        continue;
      end if;

      if not (case v_tramo.disparador_tipo
        when 'pct_cobrado_suelo' then
          v_precio_suelo > 0 and (v_cobrado_suelo / v_precio_suelo * 100) >= v_tramo.umbral
        when 'pct_cobrado_obra' then
          v_precio_construccion > 0 and (v_cobrado_obra / v_precio_construccion * 100) >= v_tramo.umbral
        when 'pct_cobrado_total' then public._comisiones_precio_total_todos(v_raiz_id) > 0 and (v_cobrado_total / public._comisiones_precio_total_todos(v_raiz_id) * 100) >= v_tramo.umbral
        when 'pct_cobrado_suelo_firmado' then
          v_suelo_firm > 0 and (v_cob_suelo_firm / v_suelo_firm * 100) >= v_tramo.umbral
        when 'pct_cobrado_obra_firmada' then
          v_obra_firm > 0 and (v_cob_obra_firm / v_obra_firm * 100) >= v_tramo.umbral
        when 'obra_firmada' then v_obra_firmada
        when 'contrato_firmado' then v_contrato_firmado
        else false
      end) then
        continue;
      end if;

      if v_condicion.base_calculo = 'importe_fijo' then
        v_importe := round(v_condicion.importe_fijo * v_tramo.pct_tramo / 100, 2);
      else
        if v_base is null then
          continue;
        end if;
        v_importe := round((coalesce(v_pct_efectivo, v_condicion.pct_comision) / 100) * v_base * (v_tramo.pct_tramo / 100), 2);
      end if;

      if coalesce(v_importe, 0) <= 0 then
        continue;
      end if;

      v_snap := jsonb_build_object(
          'recibi_id', v_ultimo_recibi_id,
          'recibi_registrado_en', v_ultimo_recibi_en,
          'disparador_tipo', v_tramo.disparador_tipo,
          'umbral', v_tramo.umbral,
          'pct_tramo', v_tramo.pct_tramo,
          'tramo_orden', v_tramo.orden,
          'base_calculo', v_base_ef,
          'base_calculo_condicion', v_condicion.base_calculo,
          'base_valor', v_base,
          'pct_comision', coalesce(v_pct_efectivo, v_condicion.pct_comision),
          'plantilla_pct', case when v_pct_efectivo is not null then v_plt_pct end,
          'vigente_desde', v_condicion.vigente_desde,
          'precio_total', v_precio_total,
          'precio_suelo', v_precio_suelo,
          'precio_construccion', v_precio_construccion,
          'cobrado_suelo', v_cobrado_suelo,
          'cobrado_obra', v_cobrado_obra,
          'cobrado_total', v_cobrado_total,
          'precio_suelo_firmado', v_suelo_firm,
          'precio_obra_firmada', v_obra_firm,
          'cobrado_suelo_firmado', v_cob_suelo_firm,
          'cobrado_obra_firmada', v_cob_obra_firm,
          'cobrado_directo_suelo', v_cob_dir_suelo,
          'cobrado_directo_obra', v_cob_dir_obra,
          'cobrado_cartas', v_cob_cartas,
          'obra_firmada', v_obra_firmada,
          'contrato_firmado', v_contrato_firmado,
          'fecha_venta', v_fecha_venta,
          'equipo_id', case when v_propia_modo then null else v_equipo_id end,
          'reclamacion_id', v_propia.id,
          'modo', v_modo,
          'condicion_fijada', v_cond_fija is not null
        );

      v_devengo_id := null;

      if v_prev.id is not null then
        v_creados := v_creados + 1;
        if public._comision_devengo_reponer(v_prev.id, v_importe, v_snap,
                                            'La venta vuelve a «' || coalesce(v_modo, 'equipo') || '»')
           or v_nivel not in ('manager', 'estandar', 'propia') then
          continue;
        end if;
        v_devengo_id := v_prev.id;
      else
        insert into public.comisiones_devengadas (
          contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel,
          importe, moneda, tipo_cambio_aplicado, disparado_por_snapshot
        ) values (
          v_raiz_id, v_tramo.id, v_condicion.id, v_beneficiario, v_nivel,
          v_importe, v_moneda, null, v_snap
        )
        on conflict (contrato_raiz_id, tramo_id, beneficiario_email) do nothing
        returning id into v_devengo_id;

        if v_devengo_id is null then
          continue;
        end if;

        v_creados := v_creados + 1;
      end if;

      if v_nivel in ('manager', 'estandar', 'propia') then
        v_creado_por := coalesce(
          auth.uid(),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_beneficiario) and u.activo limit 1),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_closer_email) and u.activo limit 1),
          (select u.user_id from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1)
        );

        v_concepto := 'Comisión ' || case v_nivel when 'manager' then 'manager' when 'propia' then 'venta propia' else 'estándar' end
          || ' — tramo ' || v_tramo.orden || ' (' || v_tramo.disparador_tipo
          || case when v_tramo.umbral is not null then ' ' || v_tramo.umbral || '%' else '' end || ')'
          || case when v_condicion.base_calculo = 'importe_fijo'
               then ' — importe fijo ' || v_condicion.importe_fijo
               else ' — ' || coalesce(v_pct_efectivo, v_condicion.pct_comision) || '% s/ '
                    || case v_base_ef
                         when 'precio_suelo_firmado' then 'precio firmado de la parcela'
                         when 'precio_obra_firmada'  then 'precio firmado de la construcción'
                         else replace(v_base_ef, '_', ' ')
                       end
                    || ' a fecha de disparo: ' || round(v_base, 2) || ' ' || v_moneda
             end
          || ' × ' || v_tramo.pct_tramo || '% del tramo — importe BRUTO (retención al pagar)';

        if v_creado_por is null then
          raise warning 'comisiones_evaluar_contrato: sin creado_por resoluble para la solicitud de % (raiz %) -- devengo % sin solicitud',
            v_beneficiario, v_raiz_id, v_devengo_id;
        else
          v_sp_id := null;
          begin
            insert into public.solicitudes_pago (
              contrato_id, concepto, importe, moneda, origen, beneficiario_email, creado_por
            ) values (
              v_raiz_id, v_concepto, v_importe, v_moneda, 'comision_automatica', v_beneficiario, v_creado_por
            )
            returning id into v_sp_id;

            update public.comisiones_devengadas
               set solicitud_id = v_sp_id
             where id = v_devengo_id;
          exception when others then
            raise warning 'comisiones_evaluar_contrato: fallo creando la solicitud de pago de % (raiz %, tramo %): % -- devengo % sin solicitud',
              v_beneficiario, v_raiz_id, v_tramo.id, sqlerrm, v_devengo_id;
          end;
        end if;
      end if;
    end loop;
  end loop;

  return v_creados;
end;
$function$;

-- 9 · reconciliador: base efectiva de cada devengo (definición viva del 13-oct + base por tramo)
create or replace function public.comisiones_reconciliar(p_raiz uuid, p_simular boolean default true, p_origen jsonb default '{}'::jsonb)
 returns table(devengo_id uuid, venta text, beneficiario text, nivel text, estado_devengo text, base_antes numeric, base_despues numeric, vigente numeric, nuevo numeric, delta numeric, accion text, motivo text)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  r record; v_sp public.solicitudes_pago;
  v_es_raiz boolean; v_moneda text; v_num text; v_base numeric;
  v_vig numeric; v_nuevo numeric; v_delta numeric; v_base_antes numeric;
  v_lawang boolean; v_manual boolean; v_accion text; v_motivo text;
  v_yo text := lower(coalesce(auth.email(), ''));
  v_dif public.comisiones_diferencias; v_dif_id uuid;
  v_hoy text := to_char(now() at time zone 'Asia/Makassar', 'DD-MM-YYYY');
  v_eq_id uuid; v_fecha_venta date; v_mismo_equipo boolean;   -- AXW-98 / B3c, por devengo
  v_precio_total numeric; v_suelo_firm numeric; v_obra_firm numeric;   -- 13-oct-2026: base por tramo
  v_multimoneda boolean;                                                -- 13-oct-2026: familia en más de una moneda
begin
  if p_raiz is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  select (c.contrato_padre_id is null and c.liberado_en is null), c.moneda, c.numero
    into v_es_raiz, v_moneda, v_num
    from public.contratos c where c.id = p_raiz;
  v_precio_total := public._comisiones_precio_total(p_raiz);
  select b.suelo_firmado, b.obra_firmada, b.multimoneda into v_suelo_firm, v_obra_firm, v_multimoneda
    from public._comisiones_bases_firmadas(p_raiz) b;

  for r in
    select d.*, c.base_calculo,
           case when c.base_calculo = 'importe_fijo' then 'importe_fijo'
                else coalesce(t.base_calculo, c.base_calculo) end as base_ef,
           case when d.disparado_por_snapshot->>'plantilla_pct' is not null then nullif(d.disparado_por_snapshot->>'pct_comision', '')::numeric else c.pct_comision end as pct_comision, c.importe_fijo, t.pct_tramo
      from public.comisiones_devengadas d
      join public.condiciones_comision c on c.id = d.condicion_id
      join public.condicion_tramos t on t.id = d.tramo_id
     where d.contrato_raiz_id = p_raiz and d.estado <> 'anulada'
     order by d.created_at, d.id
  loop
    -- solo las bases que se mueven con el contrato; una base desconocida (o nula) no se toca: falla cerrado
    continue when r.base_ef is null or r.base_ef not in ('precio_total', 'precio_suelo_firmado', 'precio_obra_firmada');
    -- 13-oct-2026 (Administración): con contratos firmados en más de una moneda las bases «firmadas» no se mueven (igual
    -- que el motor no devenga): ni diferencia ni actualización hasta que se resuelva
    if coalesce(v_multimoneda, false) and r.base_ef in ('precio_suelo_firmado', 'precio_obra_firmada') then
      raise warning 'comisiones_reconciliar: la venta (raiz %) tiene contratos firmados en mas de una moneda; el devengo % no se reconcilia', p_raiz, r.id;
      continue;
    end if;
    v_base := case r.base_ef
                when 'precio_total'         then v_precio_total
                when 'precio_suelo_firmado' then v_suelo_firm
                else v_obra_firm
              end;

    v_lawang := r.nivel in ('manager', 'estandar', 'propia');
    v_sp := null;
    if r.solicitud_id is not null then
      select * into v_sp from public.solicitudes_pago sp where sp.id = r.solicitud_id;
    end if;
    select * into v_dif from public.comisiones_diferencias x where x.devengo_id = r.id and x.estado = 'revisar';

    v_base_antes := coalesce(
      (select x.base_despues from public.comisiones_diferencias x
        where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')
        order by x.created_at desc limit 1),
      nullif(r.disparado_por_snapshot->>'base_valor', '')::numeric);
    v_vig := (case when v_lawang and v_sp.id is not null then v_sp.importe
                   else coalesce(r.importe_ajustado, r.importe) end)
           + coalesce((select sum(x.importe) from public.comisiones_diferencias x
                        where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')), 0);
    v_nuevo := round((r.pct_comision / 100) * v_base * (r.pct_tramo / 100), 2);
    v_delta := round(v_nuevo - v_vig, 2);
    v_manual := r.importe_ajustado is not null or (v_sp.id is not null and v_sp.importe_editado_por is not null);

    v_mismo_equipo := false;
    if v_delta > 0 and nullif(v_yo, '') is not null and r.nivel <> 'estandar' then
      v_eq_id := coalesce(nullif(r.disparado_por_snapshot->>'equipo_id', '')::uuid,
                          (select x.equipo_id from public._equipo_de_venta(p_raiz) x limit 1));
      if v_eq_id is not null then
        v_fecha_venta := coalesce((select x.fecha from public._equipo_de_venta(p_raiz) x limit 1), current_date);
        v_mismo_equipo :=
             exists (select 1 from public._equipo_de_venta(p_raiz) x
                      where x.equipo_id = v_eq_id and v_yo in (lower(x.manager_email), lower(x.closer_email)))
          or exists (select 1 from public.contrato_roles_equipo re
                      where re.contrato_raiz_id = p_raiz and re.equipo_id = v_eq_id and lower(re.email) = v_yo)
          or exists (select 1 from public.reclamaciones_venta_propia rp
                      where rp.contrato_raiz_id = p_raiz and rp.equipo_id = v_eq_id and rp.estado = 'aprobada'
                        and lower(rp.solicitante_email) = v_yo)
          or exists (select 1 from public.equipos_venta ev where ev.id = v_eq_id and lower(ev.manager_email) = v_yo)
          or exists (select 1 from public.equipo_miembros em
                      where em.equipo_id = v_eq_id and lower(em.closer_email) = v_yo
                        and ((em.desde <= v_fecha_venta and (em.hasta is null or em.hasta >= v_fecha_venta))
                          or (em.desde <= current_date and (em.hasta is null or em.hasta >= current_date))));
      end if;
    end if;

    v_accion := null; v_motivo := null;
    if not coalesce(v_es_raiz, false) then
      v_accion := 'revisar'; v_motivo := 'la venta ' || coalesce(v_num, '?') || ' ya no es una venta viva (traspasada a otro contrato o liberada)';
      v_delta := null;
    elsif v_moneda is distinct from r.moneda then
      v_accion := 'revisar'; v_motivo := 'la venta está ahora en ' || coalesce(v_moneda, '?') || ' y la comisión en ' || r.moneda;
      v_delta := null;
    elsif abs(v_delta) < 0.01 then
      v_accion := 'nada';
    elsif v_nuevo <= 0 then
      v_accion := 'revisar';
      v_motivo := case r.base_ef
                    when 'precio_suelo_firmado' then 'sin contratos de parcela firmados en la venta la comisión bajaría a 0'
                    when 'precio_obra_firmada'  then 'sin contrato de construcción firmado en la venta la comisión bajaría a 0'
                    else 'sin contratos firmados en la venta la comisión bajaría a 0'
                  end;
    elsif v_manual then
      v_accion := 'revisar'; v_motivo := 'el importe se había ajustado a mano';
    elsif r.estado = 'en_disputa' then
      v_accion := 'revisar'; v_motivo := 'la comisión está en disputa';
    elsif v_lawang and (v_sp.id is null or v_sp.estado in ('rechazada', 'anulada')) then
      v_accion := 'revisar'; v_motivo := 'su solicitud de pago está ' || coalesce(v_sp.estado, 'sin crear');
    elsif v_delta > 0 and lower(r.beneficiario_email) = v_yo then
      v_accion := 'revisar'; v_motivo := 'la subida la provoca quien cobra la comisión';
    elsif v_delta > 0 and v_mismo_equipo then
      v_accion := 'revisar';
      v_motivo := 'subida_mismo_equipo: la subida beneficia a alguien del mismo equipo de la venta que quien provocó el cambio; la decide otra persona';
    elsif r.nivel in ('closer', 'setter', 'team_lead') then
      v_accion := 'actualizar';   -- F9M5-informativo: informativo (nunca un pago de la empresa): se actualiza en su sitio, sin diferencia
    elsif r.estado = 'pendiente' and (not v_lawang or v_sp.estado = 'pendiente')
          and not exists (select 1 from public.comisiones_diferencias x
                           where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')) then
      v_accion := 'actualizar';
    else
      v_accion := 'diferencia';
      v_motivo := 'la comisión ya estaba '
                  || case when r.estado = 'pagada' or v_sp.estado = 'pagada' then 'pagada' else 'aprobada' end
                  || case when v_delta > 0 then ': se paga la diferencia' else ': la diferencia se descuenta de un pago siguiente' end;
    end if;

    if v_accion = 'revisar' and exists (
         select 1 from public.comisiones_diferencias x
          where x.devengo_id = r.id and x.estado = 'anulada' and x.importe_nuevo is not distinct from v_nuevo
            and x.resuelto_por is not null and x.resuelto_por <> 'sistema') then
      v_accion := 'descartada';
    end if;

    if v_accion <> 'nada' or v_dif.id is not null then
      devengo_id := r.id; venta := v_num; beneficiario := r.beneficiario_email; nivel := r.nivel;
      estado_devengo := r.estado; base_antes := v_base_antes; base_despues := v_base;
      vigente := v_vig; nuevo := v_nuevo; delta := v_delta;
      accion := case when v_accion = 'nada' then 'cierra_revisar' else v_accion end;
      motivo := v_motivo;
      return next;
    end if;
    continue when p_simular;

    perform set_config('app.via_recalculo_comision', 'on', true);

    if v_accion = 'nada' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'la comisión vuelve a cuadrar sola con la base de hoy'
         where id = v_dif.id;
      end if;

    elsif v_accion = 'actualizar' then
      update public.comisiones_devengadas d
         set importe = v_nuevo,
             disparado_por_snapshot = d.disparado_por_snapshot
               || jsonb_build_object('base_valor', v_base, 'precio_total', v_precio_total,
                                     'recalculado_en', now(), 'recalculo_origen', p_origen,
                                     'importe_motor_original', coalesce(d.disparado_por_snapshot->'importe_motor_original', to_jsonb(r.importe)),
                                     'base_original', coalesce(d.disparado_por_snapshot->'base_original', d.disparado_por_snapshot->'base_valor'))
       where d.id = r.id;
      if v_sp.id is not null then
        update public.solicitudes_pago sp
           set importe = v_nuevo,
               concepto = case
                 when sp.concepto ~ '(a fecha de disparo|recalculada el [0-9-]+): [0-9.]+ [A-Z]{3}'
                   then regexp_replace(sp.concepto, '(a fecha de disparo|recalculada el [0-9-]+): [0-9.]+ [A-Z]{3}',
                                       'recalculada el ' || v_hoy || ': ' || round(v_base, 2) || ' ' || sp.moneda)
                 else sp.concepto || ' — recalculada el ' || v_hoy || ' sobre ' || round(v_base, 2) || ' ' || sp.moneda
               end
         where sp.id = v_sp.id;
      end if;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
      values ('comisiones_devengadas', r.id, 'recalculo_auto', v_vig, v_nuevo, r.estado, r.estado,
              'cambio en el contrato: base ' || coalesce(round(v_base_antes, 2)::text, '?') || ' → ' || round(v_base, 2) || ' ' || r.moneda,
              jsonb_build_object('origen', p_origen, 'solicitud_id', v_sp.id));

    elsif v_accion = 'descartada' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'un administrador ya descartó este mismo importe'
         where id = v_dif.id;
      end if;

    elsif v_accion = 'revisar' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set importe = v_delta, importe_vigente = v_vig, importe_nuevo = v_nuevo,
               base_despues = v_base, motivo = v_motivo, origen = p_origen
         where id = v_dif.id;
      else
        insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                   motivo, estado, origen, provocado_por)
        values (r.id, v_delta, v_vig, v_nuevo, v_base_antes, v_base, v_motivo, 'revisar', p_origen, nullif(v_yo, ''))
        returning id into v_dif_id;
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
        values ('comisiones_diferencias', v_dif_id, 'diferencia', v_vig, v_nuevo, null, 'revisar', v_motivo, jsonb_build_object('origen', p_origen));
      end if;

    elsif v_accion = 'diferencia' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'sustituida por una diferencia automática'
         where id = v_dif.id;
      end if;
      insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                 motivo, estado, origen, provocado_por)
      values (r.id, v_delta, v_vig, v_nuevo, v_base_antes, v_base, v_motivo, 'pendiente', p_origen, nullif(v_yo, ''))
      returning id into v_dif_id;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
      values ('comisiones_diferencias', v_dif_id, 'diferencia', v_vig, v_nuevo, null, 'pendiente', v_motivo, jsonb_build_object('origen', p_origen));
      perform public._comision_diferencia_solicitud(v_dif_id);
    end if;

    perform set_config('app.via_recalculo_comision', 'off', true);
  end loop;
end $function$;

-- 10 · lecturas: la base del tramo llega al editor, al closer, a la trazabilidad y a la solicitud
create or replace function public.condiciones_comision_datos()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_co jsonb; v_nco int; v_tr jsonb; v_ntr int;
begin
  if public.uid_sesion() is null then
    raise exception 'condiciones_comision_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'equipo_id', c.equipo_id, 'proyecto_id', c.proyecto_id,
                                               'nivel', c.nivel, 'closer_email', c.closer_email,
                                               'pct_comision', c.pct_comision, 'base_calculo', c.base_calculo,
                                               'importe_fijo', c.importe_fijo, 'activo', c.activo,
                                               'vigente_desde', c.vigente_desde, 'vigente_hasta', c.vigente_hasta,
                                               'created_at', c.created_at, 'sustituye_a', c.sustituye_a,
                                               'empresa', c.empresa)
                            order by c.rn) filter (where c.rn <= 2000), '[]'::jsonb), count(*)::int
    into v_co, v_nco
    from (select x.id, x.equipo_id, x.proyecto_id, x.nivel, x.closer_email, x.pct_comision, x.base_calculo,
                 x.importe_fijo, x.activo, x.vigente_desde, x.vigente_hasta, x.created_at, x.sustituye_a, x.empresa,
                 row_number() over (order by x.created_at desc, x.id) as rn
            from public.condiciones_comision x order by x.created_at desc, x.id limit 2001) c;
  -- 13-oct-2026: cada tramo con su base (null = hereda) y la base efectiva con la que calcula el motor
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'condicion_id', t.condicion_id, 'orden', t.orden,
                                               'disparador_tipo', t.disparador_tipo, 'umbral', t.umbral,
                                               'pct_tramo', t.pct_tramo, 'base_calculo', t.base_calculo,
                                               'base_efectiva', t.base_efectiva)
                            order by t.rn) filter (where t.rn <= 10000), '[]'::jsonb), count(*)::int
    into v_tr, v_ntr
    from (select x.id, x.condicion_id, x.orden, x.disparador_tipo, x.umbral, x.pct_tramo, x.base_calculo,
                 case when c.base_calculo = 'importe_fijo' then 'importe_fijo'
                      else coalesce(x.base_calculo, c.base_calculo) end as base_efectiva,
                 row_number() over (order by x.orden, x.id) as rn
            from public.condicion_tramos x
            join public.condiciones_comision c on c.id = x.condicion_id
           order by x.orden, x.id limit 10001) t;
  return jsonb_build_object('condiciones', v_co, 'tramos', v_tr,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'condiciones' k where v_nco > 2000
                                            union all select 'tramos' where v_ntr > 10000) r));
end $function$;

create or replace function public.comision_de_solicitud_datos(p_solicitud uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_lista jsonb; v_n int;
begin
  if public.uid_sesion() is null then
    raise exception 'comision_de_solicitud_datos: sin sesión' using errcode = '42501';
  end if;
  -- 13-oct-2026: + base del tramo con la que se calculó (del congelado del devengo)
  select coalesce(jsonb_agg(jsonb_build_object('estado', x.estado, 'pagado_en', x.pagado_en, 'importe', x.importe,
                                               'importe_ajustado', x.importe_ajustado, 'moneda', x.moneda,
                                               'base_calculo', x.base_calculo, 'base_valor', x.base_valor,
                                               'tramo_orden', x.tramo_orden, 'disparador_tipo', x.disparador_tipo,
                                               'umbral', x.umbral)), '[]'::jsonb),
         count(*)::int
    into v_lista, v_n
    from (select d.estado, d.pagado_en, d.importe, d.importe_ajustado, d.moneda,
                 d.disparado_por_snapshot->>'base_calculo' as base_calculo,
                 nullif(d.disparado_por_snapshot->>'base_valor', '')::numeric as base_valor,
                 nullif(d.disparado_por_snapshot->>'tramo_orden', '')::int as tramo_orden,
                 d.disparado_por_snapshot->>'disparador_tipo' as disparador_tipo,
                 nullif(d.disparado_por_snapshot->>'umbral', '')::numeric as umbral
            from public.comisiones_devengadas d
           where d.solicitud_id = p_solicitud and d.nivel in ('manager', 'estandar', 'propia')
           limit 2) x;
  return jsonb_build_object('comision', case when v_n = 1 then v_lista -> 0 end);
end $function$;

-- 10a · quién ve la operación COMPLETA de un devengo: UNA regla (era la línea `v_completa` de comision_trazabilidad,
--       sin cambiar), que usan comision_trazabilidad y comisiones_reparto_datos para recortar el snapshot. Dueño
--       postgres: las lecturas de condiciones_comision y contrato_closer no pasan por la RLS del que llama (si pasaran
--       y volvieran null, es_manager_de_equipo(null) le ocultaría los datos a un SM que hoy sí los ve).
create or replace function public._comision_vista_completa(p_nivel text, p_condicion uuid, p_raiz uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce(public.puede_reparto_de(public._empresa_de_contrato_int(p_raiz)), false)
      or (p_nivel in ('closer', 'setter', 'team_lead') and (
            coalesce(public.es_manager_de_equipo((select c.equipo_id from public.condiciones_comision c where c.id = p_condicion)), false)
         or coalesce(public.es_manager_de_equipo((select k.equipo_id from public.contrato_closer k where k.contrato_id = p_raiz)), false)));
$function$;
revoke all on function public._comision_vista_completa(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public._comision_vista_completa(text, uuid, uuid) to lw_lector, service_role;

create or replace function public.comision_trazabilidad(p_devengo uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare d public.comisiones_devengadas; v_yo text := lower(coalesce(auth.email(), '')); v_completa boolean;
  v_base numeric; v_operacion numeric; v_hay_obra boolean; v_pc numeric;
  v_por_firmar jsonb; v_suma_pend numeric; v_sin_obra numeric; v_es_total boolean; v_falta numeric;
  v_base_ef text; v_suelo_firm numeric; v_obra_firm numeric; v_parte_obra boolean;
begin
  if auth.uid() is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if v_yo = '' then raise exception 'Tu sesión no trae correo: no se puede ver la trazabilidad' using errcode = '42501'; end if;
  select * into d from public.comisiones_devengadas where id = p_devengo;
  -- F4: el criterio de entrada es comision_visible, el mismo que la RLS de comisiones_devengadas
  if not found or not public.comision_visible(d.nivel, d.beneficiario_email, d.condicion_id, d.contrato_raiz_id) then
    raise exception 'No encuentro esa comisión entre las que puedes ver' using errcode = '42501';
  end if;
  v_completa := public._comision_vista_completa(d.nivel, d.condicion_id, d.contrato_raiz_id);

  -- 13-oct-2026: la base es la del TRAMO del devengo (precio total, parcela firmada u obra firmada)
  select case when c.base_calculo = 'importe_fijo' then 'importe_fijo' else coalesce(t.base_calculo, c.base_calculo) end
    into v_base_ef
    from public.condiciones_comision c
    left join public.condicion_tramos t on t.id = d.tramo_id
   where c.id = d.condicion_id;
  select b.suelo_firmado, b.obra_firmada into v_suelo_firm, v_obra_firm
    from public._comisiones_bases_firmadas(d.contrato_raiz_id) b;
  v_base := case v_base_ef
              when 'precio_suelo_firmado' then v_suelo_firm
              when 'precio_obra_firmada'  then v_obra_firm
              else public._comisiones_precio_total(d.contrato_raiz_id)
            end;
  v_es_total := v_base_ef = 'precio_total';
  v_parte_obra := v_base_ef = 'precio_obra_firmada';

  -- falta por firmar (12-oct-2026): lo que entraría en la base y aún no está firmado. Con base precio_total, todo
  -- contrato vivo salvo la carta hija; con base por parte (13-oct), solo los de esa parte y nunca una carta. Con otra
  -- base (suelo/construcción de la unidad, importe fijo) el reconciliador no la mueve: falta = 0.
  v_suma_pend := 0; v_por_firmar := '[]'::jsonb;
  if coalesce(v_es_total, false) then
    -- un borrador por tipo (el más reciente) y ninguno si ya hay firmado otro de ese tipo; misma moneda
    select coalesce(jsonb_agg(jsonb_build_object('numero', p.numero, 'tipo', p.tipo, 'precio_total', p.precio_total,
                                                 'moneda', p.moneda) order by p.created_at), '[]'::jsonb),
           coalesce(sum(p.precio_total), 0)
      into v_por_firmar, v_suma_pend
      from (select distinct on (c.tipo) c.numero, c.tipo, c.precio_total, c.moneda, c.created_at
              from public.contratos c
             where (c.id = d.contrato_raiz_id or c.contrato_padre_id = d.contrato_raiz_id)
               and not coalesce(c.bloqueado, false) and c.liberado_en is null
               and c.moneda is not distinct from d.moneda
               and not (c.contrato_padre_id is not null and c.tipo like 'carta_reserva%')
               and not exists (select 1 from public.contratos s
                                where (s.id = d.contrato_raiz_id or s.contrato_padre_id = d.contrato_raiz_id)
                                  and s.tipo = c.tipo and coalesce(s.bloqueado, false) and s.liberado_en is null)
             order by c.tipo, c.created_at desc) p;
    select coalesce(sum(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0)), 0),
           coalesce(sum(coalesce(u.precio_construccion, 0)), 0)
      into v_operacion, v_pc
      from public.unidades u where u.contrato_id = d.contrato_raiz_id;
    v_hay_obra := exists (select 1 from public.contratos h
                           where h.contrato_padre_id = d.contrato_raiz_id
                             and h.tipo like 'construccion%' and h.liberado_en is null);
    -- la obra sin contrato solo si ni lo firmado ni lo pendiente llegan al precio de la parcela (no contar dos veces)
    v_sin_obra := case when v_pc > 0 and not v_hay_obra and v_base + v_suma_pend < v_operacion then v_pc end;
  elsif v_base_ef in ('precio_suelo_firmado', 'precio_obra_firmada') then
    select coalesce(jsonb_agg(jsonb_build_object('numero', p.numero, 'tipo', p.tipo, 'precio_total', p.precio_total,
                                                 'moneda', p.moneda) order by p.created_at), '[]'::jsonb),
           coalesce(sum(p.precio_total), 0)
      into v_por_firmar, v_suma_pend
      from (select distinct on (c.tipo) c.numero, c.tipo, c.precio_total, c.moneda, c.created_at
              from public.contratos c
              left join public.contrato_tipo_etapa e on e.tipo = c.tipo
             where (c.id = d.contrato_raiz_id or c.contrato_padre_id = d.contrato_raiz_id)
               and not coalesce(c.bloqueado, false) and c.liberado_en is null
               and c.moneda is not distinct from d.moneda
               and coalesce(c.tipo, '') not like 'carta_reserva%'
               and public._comisiones_parte_obra(c.tipo, e.es_obra) = v_parte_obra
               and not exists (select 1 from public.contratos s
                                where (s.id = d.contrato_raiz_id or s.contrato_padre_id = d.contrato_raiz_id)
                                  and s.tipo = c.tipo and coalesce(s.bloqueado, false) and s.liberado_en is null)
             order by c.tipo, c.created_at desc) p;
    -- un devengo de obra solo existe con obra firmada; uno de parcela no espera obra: sin «obra sin contrato»
    v_sin_obra := null;
  end if;
  v_falta := v_suma_pend + coalesce(v_sin_obra, 0);

  return jsonb_build_object(
    'venta', d.contrato_raiz_id,
    'completa', v_completa,
    'base_calculo', v_base_ef,
    'base_hoy', v_base,
    -- quien no ve la operación completa solo sabe SI falta algo (sin cifras: con un solo contrato pendiente, la
    -- suma sería su precio, que el recorte de 050714 le oculta)
    'falta_algo', v_falta > 0,
    'por_firmar', case when v_completa then v_por_firmar else '[]'::jsonb end,
    'sin_contrato_obra', case when v_completa then v_sin_obra end,
    'falta_por_firmar', case when v_completa then v_falta end,
    'operacion', case when not v_completa then '[]'::jsonb else (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'numero', c.numero, 'tipo', c.tipo, 'precio_total', c.precio_total, 'moneda', c.moneda,
               'firmado', coalesce(c.bloqueado, false), 'fecha_firma', c.fecha_firma,
               'liberado', c.liberado_en is not null, 'es_raiz', c.id = d.contrato_raiz_id,
               'cuenta_en_base', case
                 when v_base_ef in ('precio_suelo_firmado', 'precio_obra_firmada') then
                   coalesce(c.bloqueado, false) and c.liberado_en is null
                   and c.moneda is not distinct from d.moneda
                   and coalesce(c.tipo, '') not like 'carta_reserva%'
                   and public._comisiones_parte_obra(c.tipo, e.es_obra) = v_parte_obra
                 else coalesce(c.bloqueado, false) and c.liberado_en is null
                      and not (c.contrato_padre_id is not null and c.tipo like 'carta_reserva%')
               end)
             order by (c.id = d.contrato_raiz_id) desc, c.created_at), '[]'::jsonb)
        from public.contratos c
        left join public.contrato_tipo_etapa e on e.tipo = c.tipo
       where c.id = d.contrato_raiz_id or c.contrato_padre_id = d.contrato_raiz_id) end,
    'parcelas', case when not v_completa then '[]'::jsonb else (
      select coalesce(jsonb_agg(jsonb_build_object('codigo', u.codigo, 'proyecto', u.proyecto) order by u.codigo_orden, u.codigo), '[]'::jsonb)
        from public.unidades u where u.contrato_id = d.contrato_raiz_id) end,
    'solicitud', (
      select jsonb_build_object('numero', sp.numero, 'estado', sp.estado, 'importe', sp.importe, 'moneda', sp.moneda)
        from public.solicitudes_pago sp where sp.id = d.solicitud_id),
    'diferencias', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', x.id, 'numero', x.numero, 'importe', x.importe, 'estado', x.estado, 'motivo', x.motivo,
               'base_antes', x.base_antes, 'base_despues', x.base_despues, 'vigente', x.importe_vigente,
               'nuevo', x.importe_nuevo,
               'origen', case when v_completa then x.origen
                              else jsonb_build_object('en', x.origen->'en', 'cambio', coalesce((
                                     select jsonb_agg(k.campo order by k.campo)
                                       from (values ('precio_total'), ('firmado'), ('padre'), ('tipo'), ('liberado'), ('moneda')) k(campo)
                                      where x.origen->k.campo->'antes' is distinct from x.origen->k.campo->'despues'
                                        and x.origen ? k.campo), '[]'::jsonb)) end,
               'provocado_por', case when v_completa then x.provocado_por end,
               'resuelto_por', case when v_completa then x.resuelto_por end,
               'resuelto_en', x.resuelto_en, 'resolucion_motivo', x.resolucion_motivo,
               'solicitud', (select jsonb_build_object('numero', sp.numero, 'estado', sp.estado)
                               from public.solicitudes_pago sp where sp.id = x.solicitud_id),
               'creada', x.created_at) order by x.created_at), '[]'::jsonb)
        from public.comisiones_diferencias x where x.devengo_id = d.id),
    'historial', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'en', l.creado_en, 'tabla', l.tabla, 'accion', l.accion, 'antes', l.importe_antes, 'despues', l.importe_despues,
               'estado_antes', l.estado_antes, 'estado_despues', l.estado_despues, 'motivo', l.motivo,
               'quien', case when v_completa then l.actor_email end)
             order by l.creado_en), '[]'::jsonb)
        from public.comisiones_ajustes_log l
       where (l.tabla = 'comisiones_devengadas' and l.fila_id = d.id)
          or (l.tabla = 'solicitudes_pago' and l.fila_id = d.solicitud_id)
          or (l.tabla = 'comisiones_diferencias' and l.fila_id in (select x.id from public.comisiones_diferencias x where x.devengo_id = d.id)))
  );
end
$function$;

-- 10c · comisiones_reparto_datos (definición viva del 13-oct + recorte del snapshot, hallazgo 7 de la revisión):
--       CREATE OR REPLACE conserva el dueño lw_lector y sus permisos; se comprueba al final como en 20261010101716.
create or replace function public.comisiones_reparto_datos()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_de jsonb; v_nde int; v_di jsonb; v_ndi int;
begin
  if public.uid_sesion() is null then
    raise exception 'comisiones_reparto_datos: sin sesión' using errcode = '42501';
  end if;
  -- 13-oct-2026: las 7 cifras nuevas de la operación del snapshot (parte firmada y su cobro en bruto) solo para quien ve
  -- la operación completa; misma regla que `completa` de comision_trazabilidad (_comision_vista_completa)
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'contrato_raiz_id', d.contrato_raiz_id,
                                               'beneficiario_email', d.beneficiario_email, 'nivel', d.nivel,
                                               'importe', d.importe, 'importe_ajustado', d.importe_ajustado,
                                               'ajuste_motivo', d.ajuste_motivo, 'anulado_motivo', d.anulado_motivo,
                                               'moneda', d.moneda, 'estado', d.estado, 'disparado_en', d.disparado_en,
                                               'pagado_por', d.pagado_por, 'pagado_en', d.pagado_en,
                                               'disparado_por_snapshot', case when public._comision_vista_completa(d.nivel, d.condicion_id, d.contrato_raiz_id)
                                                                              then d.disparado_por_snapshot
                                                                              else d.disparado_por_snapshot - array['precio_suelo_firmado', 'precio_obra_firmada',
                                                                                     'cobrado_suelo_firmado', 'cobrado_obra_firmada', 'cobrado_directo_suelo',
                                                                                     'cobrado_directo_obra', 'cobrado_cartas'] end)
                            order by d.rn) filter (where d.rn <= 20000), '[]'::jsonb), count(*)::int
    into v_de, v_nde
    from (select x.id, x.contrato_raiz_id, x.beneficiario_email, x.nivel, x.importe, x.importe_ajustado, x.ajuste_motivo,
                 x.anulado_motivo, x.moneda, x.estado, x.disparado_en, x.pagado_por, x.pagado_en,
                 x.disparado_por_snapshot, x.condicion_id,
                 row_number() over (order by x.disparado_en desc, x.id) as rn
            from public.comisiones_devengadas x
           where x.nivel in ('closer', 'setter', 'team_lead')
           order by x.disparado_en desc, x.id limit 20001) d;
  -- el devengo de cada diferencia se lee con la RLS de comisiones_devengadas (como el embebido de PostgREST):
  -- si el lector no lo ve, sale null.
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'numero', f.numero, 'devengo_id', f.devengo_id,
                                               'importe', f.importe, 'estado', f.estado, 'motivo', f.motivo,
                                               'created_at', f.created_at,
                                               'devengo', case when f.d_id is not null then
                                                 jsonb_build_object('nivel', f.d_nivel,
                                                                    'beneficiario_email', f.d_benef,
                                                                    'contrato_raiz_id', f.d_raiz,
                                                                    'moneda', f.d_moneda) end)
                            order by f.rn) filter (where f.rn <= 5000), '[]'::jsonb), count(*)::int
    into v_di, v_ndi
    from (select x.id, x.numero, x.devengo_id, x.importe, x.estado, x.motivo, x.created_at,
                 d.id as d_id, d.nivel as d_nivel, d.beneficiario_email as d_benef, d.contrato_raiz_id as d_raiz,
                 d.moneda as d_moneda,
                 row_number() over (order by x.created_at desc, x.id) as rn
            from public.comisiones_diferencias x
            left join public.comisiones_devengadas d on d.id = x.devengo_id
           order by x.created_at desc, x.id limit 5001) f;
  return jsonb_build_object('devengadas', v_de, 'diferencias', v_di,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'devengadas' k where v_nde > 20000
                                            union all select 'diferencias' where v_ndi > 5000) r));
end $function$;

do $$
declare v_dueno text; v_secdef boolean;
begin
  select pg_get_userbyid(p.proowner), p.prosecdef into v_dueno, v_secdef
    from pg_proc p where p.oid = 'public.comisiones_reparto_datos()'::regprocedure;
  if v_dueno <> 'lw_lector' or not v_secdef then
    raise exception 'comisiones_reparto_datos: dueño % / definer % (se esperaba lw_lector, definer)', v_dueno, v_secdef;
  end if;
  if not has_function_privilege('authenticated', 'public.comisiones_reparto_datos()', 'execute')
     or has_function_privilege('anon', 'public.comisiones_reparto_datos()', 'execute')
     or has_function_privilege('service_role', 'public.comisiones_reparto_datos()', 'execute')
     or not has_function_privilege('lw_lector', 'public._comision_vista_completa(text,uuid,uuid)', 'execute')
     or has_function_privilege('authenticated', 'public._comision_vista_completa(text,uuid,uuid)', 'execute') then
    raise exception 'comisiones_reparto_datos: permisos cambiados';
  end if;
end $$;

-- 10b · mi_condicion_comision: + columna tramos (VÁLVULA: cambiar RETURNS TABLE obliga a quitarla y crearla; se
--       reponen los permisos de la viva: postgres, service_role y authenticated)
drop function if exists public.mi_condicion_comision();
create function public.mi_condicion_comision()
 returns table(ambito text, equipo_nombre text, oculta boolean, proyecto_id uuid, nivel text, pct_comision numeric, base_calculo text, importe_fijo numeric, personal boolean, vigente_desde date, empresa text, tramos jsonb)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_yo text := lower(coalesce(auth.email(), ''));
  v_hoy date := current_date;
  v_eq record;
  v_nivel text;
  v_p uuid;
  v_emp text;
  v_c public.condiciones_comision;
  v_vistas uuid[] := '{}';
  v_claves text[] := '{}';
  v_k text;
  v_hay boolean := false;
  v_tr jsonb;
begin
  if auth.uid() is null or v_yo = '' then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  for v_eq in
    select em.equipo_id, em.rol, ev.nombre, ev.closers_ven_comision, ev.empresa
      from public.equipo_miembros em
      join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
     where lower(em.closer_email) = v_yo and em.desde <= v_hoy and (em.hasta is null or em.hasta >= v_hoy)
     order by em.created_at desc
  loop
    v_hay := true;
    if not coalesce(v_eq.closers_ven_comision, true) then
      v_k := md5(concat_ws('|', 'equipo', v_eq.nombre, 'oculta'));
      if not (v_k = any (v_claves)) then
        v_claves := v_claves || v_k;
        return query select 'equipo'::text, v_eq.nombre::text, true, null::uuid, null::text, null::numeric, null::text,
                            null::numeric, null::boolean, null::date, v_eq.empresa::text, null::jsonb;
      end if;
      continue;
    end if;
    v_nivel := case when v_eq.rol in ('closer', 'setter', 'team_lead') then v_eq.rol else 'closer' end;
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id and c.nivel = v_nivel and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      select * into v_c from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id
         and (c.proyecto_id = v_p or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and lower(c.closer_email) = v_yo
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
      if not found then
        select * into v_c from public.condiciones_comision c
         where c.equipo_id = v_eq.equipo_id
           and (c.proyecto_id = v_p or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;
      if found and not (v_c.id = any (v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        v_tr := public._condicion_tramos_resumen(v_c.id);
        v_k := md5(concat_ws('|', 'equipo', v_eq.nombre, v_c.proyecto_id, v_c.nivel, v_c.pct_comision, v_c.base_calculo, v_c.importe_fijo,
                             v_c.closer_email is not null, v_c.vigente_desde, v_tr::text));
        if not (v_k = any (v_claves)) then
          v_claves := v_claves || v_k;
          return query select 'equipo'::text, v_eq.nombre::text, false, v_c.proyecto_id, v_c.nivel, v_c.pct_comision,
                              v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde, v_eq.empresa::text, v_tr;
        end if;
      end if;
    end loop;
  end loop;
  if v_hay then return; end if;

  for v_emp in select e.clave from public.empresas e where e.activa and (not public.alcance_restringido() or public.puede_empresa(e.clave)) order by e.orden loop
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.empresa = v_emp and c.equipo_id is null and c.nivel = 'closer' and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      select * into v_c from public.condiciones_comision c
       where c.empresa = v_emp
         and c.equipo_id is null
         and c.nivel = 'closer'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.proyecto_id = v_p or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
      if found and not (v_c.id = any (v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        v_tr := public._condicion_tramos_resumen(v_c.id);
        v_k := md5(concat_ws('|', 'estandar', v_c.proyecto_id, v_c.pct_comision, v_c.base_calculo, v_c.importe_fijo,
                             v_c.closer_email is not null, v_c.vigente_desde, v_tr::text));
        if not (v_k = any (v_claves)) then
          v_claves := v_claves || v_k;
          return query select 'estandar'::text, null::text, false, v_c.proyecto_id, 'estandar'::text, v_c.pct_comision,
                              v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde, v_emp::text, v_tr;
        end if;
      end if;
    end loop;
  end loop;
end $function$;
revoke all on function public.mi_condicion_comision() from public, anon;
grant execute on function public.mi_condicion_comision() to authenticated, service_role;

-- 11 · datos: las 12 condiciones genéricas abiertas con % > 0 (medidas el 13-oct-2026, por id exacto) se cierran el
--      31-oct y nace su sucesora desde el 1-nov. Ids fijos e idempotente. No se tocan: las de 0 % y las de un closer
--      concreto (siguen ganando para su closer: el motor ordena primero la del closer), 0864530b (inactiva y sin
--      vigente_hasta: ponérsela la volvería elegible) ni las ya cerradas.
do $$
declare
  v record; c public.condiciones_comision; n public.condiciones_comision; v_hechas int := 0; v_ult date;
begin
  for v in select * from (values
      ('22de941a-7d34-4894-8b79-cafbe05d1d56'::uuid, 'c0a11010-1101-4a10-8000-000000000001'::uuid, 'c0a11010-1101-4b10-8000-000000000101'::uuid, 'c0a11010-1101-4b10-8000-000000000102'::uuid),
      ('4a1c0fe1-f3b1-49b7-a513-328939f0ec1b', 'c0a11010-1101-4a10-8000-000000000002', 'c0a11010-1101-4b10-8000-000000000201', 'c0a11010-1101-4b10-8000-000000000202'),
      ('ac9f7557-dbf6-44a4-8ae2-fa31c8d68153', 'c0a11010-1101-4a10-8000-000000000003', 'c0a11010-1101-4b10-8000-000000000301', 'c0a11010-1101-4b10-8000-000000000302'),
      ('eab39fea-b874-43dd-87a6-eec94c34efd1', 'c0a11010-1101-4a10-8000-000000000004', 'c0a11010-1101-4b10-8000-000000000401', 'c0a11010-1101-4b10-8000-000000000402'),
      ('4a1036e7-58d0-4b81-b5fd-ab0de41dcee1', 'c0a11010-1101-4a10-8000-000000000005', 'c0a11010-1101-4b10-8000-000000000501', 'c0a11010-1101-4b10-8000-000000000502'),
      ('3f774dde-e4f1-4086-85f9-c3942acc06ae', 'c0a11010-1101-4a10-8000-000000000006', 'c0a11010-1101-4b10-8000-000000000601', 'c0a11010-1101-4b10-8000-000000000602'),
      ('491d8acd-182a-4906-916d-433940a376e5', 'c0a11010-1101-4a10-8000-000000000007', 'c0a11010-1101-4b10-8000-000000000701', 'c0a11010-1101-4b10-8000-000000000702'),
      ('c7ac56ca-c0a4-4e76-82bb-6086eccdb4c9', 'c0a11010-1101-4a10-8000-000000000008', 'c0a11010-1101-4b10-8000-000000000801', 'c0a11010-1101-4b10-8000-000000000802'),
      ('ddb805c1-335a-409b-9ad7-93ba78bd9619', 'c0a11010-1101-4a10-8000-000000000009', 'c0a11010-1101-4b10-8000-000000000901', 'c0a11010-1101-4b10-8000-000000000902'),
      ('57f7369f-3801-4f77-9091-d87fd7db0268', 'c0a11010-1101-4a10-8000-000000000010', 'c0a11010-1101-4b10-8000-000000001001', 'c0a11010-1101-4b10-8000-000000001002'),
      ('286adb02-4369-4a39-94a7-6e7735440a40', 'c0a11010-1101-4a10-8000-000000000011', 'c0a11010-1101-4b10-8000-000000001101', 'c0a11010-1101-4b10-8000-000000001102'),
      ('bbca7a81-f529-4be9-99d6-feed49228009', 'c0a11010-1101-4a10-8000-000000000012', 'c0a11010-1101-4b10-8000-000000001201', 'c0a11010-1101-4b10-8000-000000001202')
    ) x(viejo, nuevo, t1, t2)
  loop
    if exists (select 1 from public.condiciones_comision s where s.id = v.nuevo) then
      v_hechas := v_hechas + 1;
      continue;
    end if;
    select * into c from public.condiciones_comision s where s.id = v.viejo for update;
    if not found or not c.activo or c.vigente_hasta is not null or c.closer_email is not null
       or c.pct_comision <= 0 or c.base_calculo <> 'precio_total' or c.vigente_desde > date '2026-10-31' then
      raise exception 'comisiones 1-nov: la condición % ya no está como se midió el 13-oct (abierta, genérica, %% > 0, precio_total)', v.viejo;
    end if;
    -- misma comprobación que _condicion_comision_guarda_en: si la migración se aplica después del 1-nov y la condición
    -- vieja ya devengó una venta de noviembre, cerrarla el 31-oct dejaría ese devengo fijado a una condición cerrada
    -- (con el 10 % del total en vez de la regla nueva). Se para: esa venta se resuelve a mano antes de aplicar.
    v_ult := public._condicion_ultima_venta_devengada(v.viejo);
    if v_ult is not null and v_ult > date '2026-10-31' then
      raise exception 'comisiones 1-nov: la condición % ya ha devengado una venta del % (posterior al 31-oct); no se puede cerrar el 31-oct sin resolver antes esa venta',
        v.viejo, to_char(v_ult, 'DD-MM-YYYY');
    end if;

    update public.condiciones_comision set vigente_hasta = date '2026-10-31' where id = v.viejo;
    insert into public.condiciones_comision_log (condicion_id, antes, despues, con_devengos, motivo, por)
    values (v.viejo, to_jsonb(c), (select to_jsonb(s) from public.condiciones_comision s where s.id = v.viejo),
            exists (select 1 from public.comisiones_devengadas d where d.condicion_id = v.viejo),
            'Regla del owner del 13-oct-2026: desde el 1-nov-2026 la comisión es 10 % de la parcela firmada al 50 % cobrado + 10 % de la construcción firmada al 25 % cobrado. Esta condición queda para las ventas hasta el 31-oct.',
            'migración comisiones_regla_1nov');

    insert into public.condiciones_comision (id, equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo,
                                             importe_fijo, activo, created_by, vigente_desde, vigente_hasta, sustituye_a, empresa)
    values (v.nuevo, c.equipo_id, c.proyecto_id, c.nivel, null, c.pct_comision, 'por_tramo',
            null, true, 'migración comisiones_regla_1nov (owner 13-oct-2026)', date '2026-11-01', null, v.viejo, c.empresa)
    returning * into n;
    insert into public.condicion_tramos (id, condicion_id, orden, disparador_tipo, umbral, pct_tramo, base_calculo)
    values (v.t1, v.nuevo, 1, 'pct_cobrado_suelo_firmado', 50, 100, 'precio_suelo_firmado'),
           (v.t2, v.nuevo, 2, 'pct_cobrado_obra_firmada', 25, 100, 'precio_obra_firmada');
    insert into public.condiciones_comision_log (condicion_id, antes, despues, con_devengos, motivo, por)
    values (v.nuevo, null, to_jsonb(n) || jsonb_build_object('tramos', public._condicion_tramos_resumen(v.nuevo)), false,
            'Regla del owner del 13-oct-2026 para ventas desde el 1-nov-2026: tramo 1 = 100 % al 50 % cobrado de la parcela firmada, sobre el precio firmado de la parcela; tramo 2 = 100 % al 25 % cobrado de la construcción firmada, sobre su precio firmado. Sustituye a ' || v.viejo || '.',
            'migración comisiones_regla_1nov');
    if public._condicion_solapa(v.nuevo) is not null or public._condicion_solapa(v.viejo) is not null then
      raise exception 'comisiones 1-nov: % / % solapan con %', v.viejo, v.nuevo,
        coalesce(public._condicion_solapa(v.nuevo), public._condicion_solapa(v.viejo));
    end if;
    v_hechas := v_hechas + 1;
  end loop;
  if v_hechas <> 12 then
    raise exception 'comisiones 1-nov: se esperaban 12 condiciones sucesoras y hay %', v_hechas;
  end if;
end $$;
