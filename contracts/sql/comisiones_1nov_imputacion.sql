-- «Primero parcela, luego obra» (migración comisiones_regla_1nov, owner 13-oct-2026). SOLO LECTURA, sin válvula.
-- Se pasa DESPUÉS de aplicar la migración: compara lo que devuelve la función real _comisiones_bases_firmadas con la
-- misma regla calculada aquí a mano (cobrado de cada contrato con la fórmula de contrato_cobrado, sin pasar por la
-- función), sobre todas las ventas vivas firmadas (raíz sin padre, no liberada, bloqueada: 54 el 13-oct).
-- Devuelve filas SOLO cuando algo está mal: la función no coincide con la regla, o alguna parte pasa del 100 %.
-- Lo que se esperaba el 13-oct (cambia si entran cobros): 54 ventas, parcela >= 50 % = 20, obra >= 25 % = 4,
-- imputado total 703.429,79 (consulta comentada al final).
-- F3 (14-oct-2026): bolsa única (lo cobrado en obra también llena primero la parcela) y guarda del Bloqueo sin firmar.
-- Medido el 14-oct con la regla nueva antes de aplicarla: 57 ventas, parcela >= 50 % = 21, obra >= 25 % = 3, imputado
-- 703.429,79, 0 desacuerdos; solo RP00132 cambia de reparto (parcela 5.000 → 25.000, obra 20.000 → 0) y 0 ventas en el
-- estado de la guarda (sin parcela firmada, con Bloqueo vivo sin firmar y obra firmada).
-- OJO (15-oct-2026, BAJA 4 del revisor): la CTE `guarda` de aquí repite la de la función, así que su acuerdo sale por
-- construcción y NO prueba la guarda. La prueba independiente son G4a–G4g de prueba_comisiones_1nov.sql (raíz y HIJA sin
-- firmar: contrato_general, Hak Sewa, otra moneda, liberada), con cifras escritas a mano. Esto solo vigila el resto.
-- 13-oct-2026 (consulta de Administración): parte = public._comisiones_parte_obra (adenda = obra, fuente única) y solo
-- cuentan contratos, recibís y facturas en la moneda de la raíz; una venta multimoneda sale como fila (no debería haber).
with raices as (
  select r.id as raiz, r.numero, r.moneda from public.contratos r
   where r.contrato_padre_id is null and r.liberado_en is null and coalesce(r.bloqueado, false)
), fam as (
  select rz.raiz, rz.moneda, c.id, coalesce(c.precio_total, 0) as precio,
         public._comisiones_parte_obra(c.tipo, e.es_obra) as es_obra,
         coalesce(c.tipo, '') like 'carta_reserva%' as es_carta
    from raices rz
    join public.contratos c on (c.id = rz.raiz or c.contrato_padre_id = rz.raiz)
    left join public.contrato_tipo_etapa e on e.tipo = c.tipo
   where coalesce(c.bloqueado, false) and c.liberado_en is null
     and c.moneda is not distinct from rz.moneda
), cob as (
  select f.*,
         coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                     join public.facturas r on r.id = ra.recibi_id join public.facturas fa on fa.id = ra.factura_id
                    where fa.contrato_id = f.id and not coalesce(r.anulada, false) and not coalesce(fa.anulada, false)
                      and (f.moneda is null or (r.moneda is not distinct from f.moneda and fa.moneda is not distinct from f.moneda))), 0)
       + coalesce((select sum(r.total - coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                                                    join public.facturas f2 on f2.id = ra.factura_id
                                                   where ra.recibi_id = r.id and f2.contrato_id is not null
                                                     and not coalesce(f2.anulada, false)), 0))
                     from public.facturas r
                    where r.tipo = 'recibi' and r.contrato_id = f.id and not coalesce(r.anulada, false)
                      and (f.moneda is null or r.moneda is not distinct from f.moneda)), 0) as cobrado
    from fam f
), v as (
  select rz.raiz, rz.numero,
         coalesce(sum(cob.precio)  filter (where not cob.es_carta and not cob.es_obra), 0) as p,
         coalesce(sum(cob.precio)  filter (where not cob.es_carta and cob.es_obra), 0)     as o,
         coalesce(sum(cob.cobrado) filter (where not cob.es_carta and not cob.es_obra), 0) as cp,
         coalesce(sum(cob.cobrado) filter (where not cob.es_carta and cob.es_obra), 0)     as co,
         coalesce(sum(cob.cobrado) filter (where cob.es_carta), 0)                         as cc
    from raices rz left join cob on cob.raiz = rz.raiz
   group by rz.raiz, rz.numero
), guarda as (
  -- F3 (14-oct-2026): contrato vivo sin firmar en la familia (raíz o hijo); desde el 15-oct (20261015065609) de la misma
  -- clase que `p`: moneda de la raíz, ni carta ni obra (antes solo tipo = 'reserva_parcela')
  select rz.raiz, exists (select 1 from public.contratos c
                            left join public.contrato_tipo_etapa e on e.tipo = c.tipo
                           where (c.id = rz.raiz or c.contrato_padre_id = rz.raiz)
                             and not coalesce(c.bloqueado, false) and c.liberado_en is null
                             and c.moneda is not distinct from rz.moneda
                             and not coalesce(c.tipo, '') like 'carta_reserva%'
                             and not public._comisiones_parte_obra(c.tipo, e.es_obra)) as bloqueo_sin_firmar
    from raices rz
), esperado as (
  -- F3 (14-oct-2026): bolsa única de la familia firmada (parcela + cartas + obra); primero la parcela, el resto a obra.
  -- Sin parcela firmada: la obra cuenta lo cobrado en obra, salvo con un contrato de parcela vivo sin firmar (entonces 0).
  select v.*,
         case when v.p > 0 then greatest(least(v.p, v.cp + v.cc + v.co), 0) else 0 end as ip,
         greatest(least(v.o, case when v.p > 0 then v.cp + v.cc + v.co - greatest(least(v.p, v.cp + v.cc + v.co), 0)
                                  when g.bloqueo_sin_firmar then 0
                                  else v.co end), 0) as io
    from v join guarda g on g.raiz = v.raiz
)
select x.numero, x.p, x.o, x.ip as esperado_parcela, x.io as esperado_obra,
       b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada
  from esperado x
  cross join lateral public._comisiones_bases_firmadas(x.raiz) b
 where (b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
        b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas)
       is distinct from (x.p, x.o, x.ip, x.io, x.cp, x.co, x.cc)
    or b.cobrado_suelo_firmado > b.suelo_firmado
    or b.cobrado_obra_firmada > b.obra_firmada
    or b.multimoneda;

-- Recuento (no forma parte del veredicto; para comparar con lo medido el 13-oct):
-- select count(*), count(*) filter (where b.suelo_firmado > 0 and b.cobrado_suelo_firmado / b.suelo_firmado >= 0.5),
--        count(*) filter (where b.obra_firmada > 0 and b.cobrado_obra_firmada / b.obra_firmada >= 0.25),
--        sum(b.cobrado_suelo_firmado + b.cobrado_obra_firmada)
--   from public.contratos r cross join lateral public._comisiones_bases_firmadas(r.id) b
--  where r.contrato_padre_id is null and r.liberado_en is null and coalesce(r.bloqueado, false);
