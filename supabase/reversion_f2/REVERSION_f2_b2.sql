-- Reversion del bloque 2 (DINERO) de la Fase 2 (8-oct-2026): facturas, recibis, proformas, solicitudes de pago y retenciones, gastos, proveedores, bancos, cuentas de cobro y sociedades por empresa.
-- Deja la base como estaba justo antes de las migraciones 20261008200000..20261008206000 (incluida la correccion 4b):
--   1. reaplica, desde public._f2_b2_originales (instantanea tomada por la migracion 0 con pg_get_functiondef / pg_policies en vivo), las 34 funciones y las 12 policies que el bloque cambio;
--   2. borra las funciones nuevas del bloque (todas con su llamador: ayudas privadas y envoltorios de policies);
--   3. quita proveedores.empresa SOLO si ninguna fila la usa (si la usa, la deja y avisa: es dato del cliente, no se destruye).
-- Valida mientras nadie use un rol de empresa en dinero; si alguien ya emitio/gasto/concilio con un rol de empresa, esas filas se quedan (la reversion no toca datos).
-- La tabla auxiliar public._f2_b2_originales NO se borra aqui (la instantanea es la fuente de esta reversion): se retira cuando el bloque lleve una semana estable (ultima linea). La tabla temporal de la prueba ya se borro.
-- destructivo-ok: reaplica definiciones, borra funciones propias del bloque (no datos) y, solo si esta vacia, una columna nueva del bloque
begin;

do $r$
declare x record;
begin
  if (select count(*) from public._f2_b2_originales) < 46 then
    raise exception 'La instantanea public._f2_b2_originales no esta completa: no se revierte nada';
  end if;
  for x in select ddl from public._f2_b2_originales order by tipo desc loop   -- primero las policies, luego las funciones
    execute x.ddl;
  end loop;
end $r$;

drop function if exists public.retencion_admin_de_solicitud(uuid);
drop function if exists public.solicitud_admin_de_contrato(uuid);
drop function if exists public.sociedad_super_de(text);
drop function if exists public.gastos_acceso();
drop function if exists public.banco_movimiento_visible(uuid);
drop function if exists public.banco_cuenta_visible(text);
drop function if exists public.proveedor_visible(text);
drop function if exists public.gasto_ruta_visible(text);
drop function if exists public.gasto_id_visible(uuid);
drop function if exists public.gasto_visible(text, uuid);
drop function if exists public.banco_comision_visible(uuid);
drop function if exists public.bancos_acceso();
drop function if exists public._reparto_valida_empresa(jsonb, text[]);
drop function if exists public._super_o_empresa();
drop function if exists public._banco_ref_empresa(text, uuid);
drop function if exists public._bancos_puerta_de(text);
drop function if exists public._empresa_comision(uuid);
drop function if exists public._empresa_movimiento(uuid);
drop function if exists public._empresa_gasto(text, uuid);
drop function if exists public._empresa_sociedad(text);
drop function if exists public._empresa_cuenta(text);
drop function if exists public._empresa_doc(uuid, uuid);
drop function if exists public._puede_admin_de(text, text);
drop function if exists public._puede_herr_admin(text);
drop function if exists public._puede_herr(text);
drop function if exists public._super_empresa_alguna();
drop function if exists public._rol_empresa();

do $r$
begin
  if exists (select 1 from public.proveedores where empresa is not null) then
    raise notice 'proveedores.empresa tiene datos: la columna se queda (es dato de proveedores reales)';
  else
    alter table public.proveedores drop column if exists empresa;
  end if;
end $r$;

commit;

-- Cuando el bloque lleve una semana estable (y ya no haga falta poder volver atras):
--   drop table public._f2_b2_originales;
