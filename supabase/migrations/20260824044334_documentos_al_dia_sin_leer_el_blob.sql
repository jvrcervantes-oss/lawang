-- destructivo-ok: `create or replace view`, mismas columnas y orden — no borra
-- filas ni objetos, solo cambia CÓMO se resuelve el join.
-- ════════════════════════════════════════════════════════════════════════════
-- documentos_desactualizados TARDABA 4,5 SEGUNDOS EN CADA CARGA — 24-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Hallazgo de Desarrollo (auditoría pedida por el owner tras el fix de hoy de
-- `contratos_del_mismo_comprador`, la MISMA familia de bug): el rama de
-- `contrato` de esta vista unía por
--   `join public.clients cl on cl.id = (c.datos->>'adq1_client_id')::uuid`
-- — leer una clave de `datos` (el jsonb con firmas/anexos en base64, hasta
-- 7,3 MB por fila) obliga a Postgres a destoastear el valor ENTERO por cada
-- fila de `contratos` para poder evaluar el join. Medido con `explain
-- (analyze, buffers)` contra los 111 contratos reales: 4,48 SEGUNDOS y 31.535
-- buffers — la misma magnitud que los 4,27 s de `contratos_del_mismo_comprador`
-- antes de arreglarla hoy mismo.
--
-- Esta vista la lee `lwDivergencias()` (contracts/assets/ficha_divergencia.js)
-- en CADA apertura del listado de Contratos y de Facturas — no es una consulta
-- rara, es tráfico constante.
--
-- LA CURA, la misma de hoy: `contrato_compradores` ya tiene `client_id` del
-- adquiriente_1 en una tabla sin el jsonb pesado, indexada por
-- `(contrato_id, rol)` y por `client_id`, mantenida al día por
-- `sincronizar_compradores()`. Se une por ahí; los campos que SÍ hace falta
-- comparar (nombre, pasaporte, email...) se siguen leyendo de `datos`, pero
-- solo para las filas que YA hicieron match — no como condición del join sobre
-- TODAS las filas.
--
-- La rama de `factura` no se toca: ya unía por `f.client_id`, una columna
-- real, no un jsonb.

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
           'domicilio',   c.datos->'fields'->>'adq1_domicilio',
           'pais',        c.datos->'fields'->>'adq1_nacionalidad'),
         jsonb_build_object(
           'nombre', cl.full_name, 'identidad', cl.passport_number, 'email', cl.email,
           'telefono', cl.phone, 'domicilio', cl.address, 'pais', cl.nationality)
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
           'email',     f.datos->'fields'->>'cliente_email',
           'domicilio', f.datos->'fields'->>'cliente_domicilio'),
         jsonb_build_object(
           'nombre', cl.full_name, 'identidad', cl.passport_number,
           'email', cl.email, 'domicilio', cl.address)
       )
  from public.facturas f
  join public.clients cl on cl.id = f.client_id;

alter view public.documentos_desactualizados set (security_invoker = true);
grant select on public.documentos_desactualizados to authenticated;
