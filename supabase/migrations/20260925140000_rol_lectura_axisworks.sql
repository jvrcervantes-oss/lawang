-- Usuario de SOLO LECTURA para las herramientas del estudio (erp/sql.py, erp/volcado_esquema.py). 25-sep-2026,
-- OK del owner (AXW-18). Por qué: el candado de solo lectura del script falló dos veces (24 y 25-sep); con este
-- usuario, aunque el script falle, la base no deja escribir (pg_read_all_data + default_transaction_read_only).
-- La contraseña NO va aquí: la pone erp/rol_lectura.py como verificador SCRAM y vive en private/lawang_ro_db.env.
-- Aplicada con el MCP (versión registrada 20260924235340, se empareja por nombre como el resto).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'axw_lectura') then
    create role axw_lectura login bypassrls connection limit 4;
  end if;
end $$;
grant pg_read_all_data to axw_lectura;
alter role axw_lectura set default_transaction_read_only = on;
alter role axw_lectura set statement_timeout = '60s';
comment on role axw_lectura is 'AxisWorks: solo lectura para herramientas del estudio (erp/sql.py). Sin permisos de escritura.';
