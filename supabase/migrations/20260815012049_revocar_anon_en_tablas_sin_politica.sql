-- Seis tablas con RLS activa y CERO politicas: hoy no pasa nada por ellas (RLS
-- sin politica niega todo), pero `anon` conservaba GRANT de SELECT e INSERT.
-- Es una trampa a plazo: el dia que alguien anada una politica permisiva, esas
-- tablas quedan abiertas a un anonimo sin que nadie lo relacione con el cambio.
-- Quitar el GRANT no altera el comportamiento actual -- ya estaban cerradas --
-- y hace que RLS deje de ser la UNICA barrera.
-- Las axisworks_* son la facturacion del propio estudio; contrato_documentos,
-- payments y reservations estan a 0 filas.
revoke all on table public.axisworks_cuentas       from anon;
revoke all on table public.axisworks_facturas      from anon;
revoke all on table public.axisworks_meta_campanas from anon;
revoke all on table public.contrato_documentos     from anon;
revoke all on table public.payments                from anon;
revoke all on table public.reservations            from anon;;
