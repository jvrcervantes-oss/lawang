-- «Primero parcela, luego obra» (migración comisiones_regla_1nov, owner 13-oct-2026). SOLO LECTURA, sin válvula.
-- Se pasa DESPUÉS de aplicar la migración: compara lo que devuelve la función real _comisiones_bases_firmadas con la
-- misma regla calculada aquí a mano (cobrado de cada contrato con la fórmula de contrato_cobrado, sin pasar por la
-- función), sobre todas las ventas vivas firmadas (raíz sin padre, no liberada, bloqueada: 54 el 13-oct).
-- Devuelve filas SOLO cuando algo está mal: la función no coincide con la regla, o alguna parte pasa del 100 %.
-- Lo que se esperaba el 13-oct (cambia si entran cobros): 54 ventas, parcela >= 50 % = 20, obra >= 25 % = 4,
-- imputado total 703.429,79 (consulta comentada al final).
with raices as (
  select r.id as raiz, r.numero from public.contratos r
   where r.contrato_padre_id is null and r.liberado_en is null and coalesce(r.bloqueado, false)
), fam as (
  select rz.raiz, c.id, coalesce(c.precio_total, 0) as precio, coalesce(e.es_obra, false) as es_obra,
         coalesce(c.tipo, '') like 'carta_reserva%' as es_carta
    from raices rz
    join public.contratos c on (c.id = rz.raiz or c.contrato_padre_id = rz.raiz)
    left join public.contrato_tipo_etapa e on e.tipo = c.tipo
   where coalesce(c.bloqueado, false) and c.liberado_en is null
), cob as (
  select f.*,
         coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                     join public.facturas r on r.id = ra.recibi_id join public.facturas fa on fa.id = ra.factura_id
                    where fa.contrato_id = f.id and not coalesce(r.anulada, false) and not coalesce(fa.anulada, false)), 0)
       + coalesce((select sum(r.total - coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                                                    join public.facturas f2 on f2.id = ra.factura_id
                                                   where ra.recibi_id = r.id and f2.contrato_id is not null
                                                     and not coalesce(f2.anulada, false)), 0))
                     from public.facturas r
                    where r.tipo = 'recibi' and r.contrato_id = f.id and not coalesce(r.anulada, false)), 0) as cobrado
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
), esperado as (
  select v.*,
         case when v.p > 0 then greatest(least(v.p, v.cp + v.cc), 0) else 0 end as ip,
         greatest(least(v.o, v.co + case when v.p > 0
                                         then greatest(v.cp + v.cc - greatest(least(v.p, v.cp + v.cc), 0), 0)
                                         else 0 end), 0) as io
    from v
)
select x.numero, x.p, x.o, x.ip as esperado_parcela, x.io as esperado_obra,
       b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada
  from esperado x
  cross join lateral public._comisiones_bases_firmadas(x.raiz) b
 where (b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
        b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas)
       is distinct from (x.p, x.o, x.ip, x.io, x.cp, x.co, x.cc)
    or b.cobrado_suelo_firmado > b.suelo_firmado
    or b.cobrado_obra_firmada > b.obra_firmada;

-- Recuento (no forma parte del veredicto; para comparar con lo medido el 13-oct):
-- select count(*), count(*) filter (where b.suelo_firmado > 0 and b.cobrado_suelo_firmado / b.suelo_firmado >= 0.5),
--        count(*) filter (where b.obra_firmada > 0 and b.cobrado_obra_firmada / b.obra_firmada >= 0.25),
--        sum(b.cobrado_suelo_firmado + b.cobrado_obra_firmada)
--   from public.contratos r cross join lateral public._comisiones_bases_firmadas(r.id) b
--  where r.contrato_padre_id is null and r.liberado_en is null and coalesce(r.bloqueado, false);
