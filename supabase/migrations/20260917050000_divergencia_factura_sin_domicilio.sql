-- 17-sep-2026 · El domicilio sale también de facturas y recibís (owner:
-- "elimina el domicilio de las facturas y recibís"). Ayer
-- (20260917020000_divergencia_contrato_sin_domicilio) se quitó solo de la
-- mitad de CONTRATO de esta vista, dejando la de factura comparando
-- `cliente_domicilio` contra `clients.address` — con el campo ya fuera del
-- documento y de la ficha (17-sep, retirado del formulario de compradores),
-- ese aviso saltaría sin que el operador pudiera hacer nada con él: no hay
-- dónde traer el dato ni dónde corregirlo. Se quita de las dos mitades ahora.
-- security_invoker se vuelve a fijar (CREATE OR REPLACE VIEW lo resetea).
create or replace view public.documentos_desactualizados as
select 'contrato'::text as tipo, c.id, c.numero,
       coalesce(c.bloqueado, false) as congelado,
       cl.id as client_id, cl.full_name as ficha,
       public.diferencias_con_ficha(
         jsonb_build_object(
           'nombre',      c.datos->'fields'->>'adq1_nombre',
           'identidad',   c.datos->'fields'->>'adq1_pasaporte',
           'email',       c.datos->'fields'->>'adq1_email',
           'telefono',    c.datos->'fields'->>'adq1_telefono',
           'pais',        c.datos->'fields'->>'adq1_nacionalidad'),
         jsonb_build_object(
           'nombre', cl.full_name, 'identidad', cl.passport_number, 'email', cl.email,
           'telefono', cl.phone, 'pais', cl.nationality)
       ) as diferencias
  from public.contratos c
  join public.contrato_compradores cc on cc.contrato_id = c.id and cc.rol = 'adquiriente_1'
  join public.clients cl on cl.id = cc.client_id
union all
select 'factura', f.id, f.numero,
       coalesce(f.anulada, false) or coalesce(f.enviada, false) as congelado,
       cl.id, cl.full_name,
       public.diferencias_con_ficha(
         jsonb_build_object(
           'nombre',    f.cliente_nombre,
           'identidad', f.datos->'fields'->>'cliente_documento',
           'email',     f.datos->'fields'->>'cliente_email'),
         jsonb_build_object(
           'nombre', cl.full_name, 'identidad', cl.passport_number,
           'email', cl.email)
       )
  from public.facturas f
  join public.clients cl on cl.id = f.client_id;

alter view public.documentos_desactualizados set (security_invoker = true);
grant select on public.documentos_desactualizados to authenticated;
