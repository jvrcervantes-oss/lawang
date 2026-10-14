-- NO APLICADA (14-oct-2026). Segundo paso de «primero la parcela, luego la obra»: la regla de comisiones de las ventas
-- desde el 1-nov (_comisiones_bases_firmadas). Hoy no hay ninguna venta con esa fecha: aplicar esto no mueve dinero
-- hasta noviembre, y por eso espera a poder probarse bien.
--
-- POR QUÉ ESPERA. Su batería (contracts/sql/prueba_comisiones_1nov.sql) solo corre con la válvula del owner abierta
-- (monta el laboratorio con session_replication_role = replica) y varios de sus casos fijan la regla anterior: hay que
-- reescribir sus cifras esperadas Y verla en verde antes de aplicar. Aplicar sin esa batería sería dinero sin probar.
-- Tiene que estar aplicada ANTES del 1-nov-2026.
--
-- QUÉ CAMBIA respecto a lo que hay en producción desde el 14-oct (migración 20261014012527):
--   1. «Lo cobrado en un contrato de obra no sube a la parcela» deja de valer (owner, 14-oct: la regla general manda
--      también en comisiones). Bolsa = todo lo cobrado en los contratos FIRMADOS de la familia: parcela + cartas + obra.
--        parcela = least(precio parcela firmada, bolsa)
--        obra    = least(precio obra firmada, bolsa - parcela)
--   2. Solo cuentan contratos FIRMADOS, como hasta ahora (owner, 28-sep: «no se paga comisión sin contrato firmado»;
--      revisión previa de Administración, 14-oct). Con el Bloqueo firmado y el dinero apuntado en una Construcción aún
--      sin firmar, la parcela no avanza hasta que se firme la Construcción: lento, pero no se puede deshacer al revés.
--   3. GUARDA NUEVA (Administración, 14-oct): si la venta tiene un Bloqueo de Parcela vivo SIN firmar, lo cobrado en
--      obra NO cuenta todavía como obra. Sin ella, una Construcción firmada con el 25 % cobrado devengaría, y al firmarse
--      el Bloqueo ese dinero pasaría a llenar la parcela con la comisión de obra ya pagada (un devengo pagado no se
--      revierte). Hoy hay 0 ventas en ese estado. Una venta sin ningún Bloqueo (obra suelta) sigue como hasta ahora.
--   Se mantienen: la carta no suma en ninguna base, adenda = obra, sin parcela firmada no hay cascada.
--
-- AL APLICARLA: copiarla a supabase/migrations/<fecha>_comisiones_1nov_primero_parcela.sql, actualizar
-- contracts/sql/prueba_comisiones_1nov.sql (casos 1–10 y C1–C5: con la bolsa única la parcela del laboratorio pasa de
-- 29.500 a 49.500 cobrados; C4b cambia de sentido; caso nuevo para la guarda) y contracts/sql/comisiones_1nov_imputacion.sql
-- (la regla «a mano» de su CTE `esperado`), y pasar las dos.

create or replace function public._comisiones_bases_firmadas(p_raiz uuid)
 returns table(suelo_firmado numeric, obra_firmada numeric, cobrado_suelo_firmado numeric, cobrado_obra_firmada numeric,
               cobrado_directo_suelo numeric, cobrado_directo_obra numeric, cobrado_cartas numeric, multimoneda boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
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
  ), g as (
    select exists (select 1 from public.contratos c
                    where (c.id = p_raiz or c.contrato_padre_id = p_raiz)
                      and c.tipo = 'reserva_parcela' and not coalesce(c.bloqueado, false)
                      and c.liberado_en is null) as bloqueo_sin_firmar
  ), i as (
    select s.*, case when s.p > 0 then greatest(least(s.p, s.cp + s.cc + s.co), 0) else 0 end as ip from s
  )
  select i.p, i.o, i.ip,
         greatest(least(i.o, case when i.p > 0 then i.cp + i.cc + i.co - i.ip
                                  when (select g.bloqueo_sin_firmar from g) then 0
                                  else i.co end), 0),
         i.cp, i.co, i.cc,
         exists (select 1 from fam f where f.moneda is distinct from (select r.moneda from r))
    from i;
$function$;
