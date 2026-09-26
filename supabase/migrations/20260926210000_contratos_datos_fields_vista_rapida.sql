-- destructivo-ok: el UPDATE de abajo solo RELLENA la columna nueva datos_fields (copia de datos->'fields') en cada contrato; no cambia ni borra ningún dato existente.
-- `documentos_desactualizados` tardaba 11,6 s (26-sep-2026) y fallaba a ratos por el statement_timeout
-- de 8 s de authenticated: el aviso de «documento desactualizado» no salía. Causa: para leer 5 campos
-- de `datos->'fields'` (<1 kB) había que descomprimir el `datos` ENTERO de cada contrato (537 kB de
-- media, 7 MB el mayor: anexos y diseño), ~39 ms por fila — reference_lawang_datos_jsonb_toast_lentitud.
-- Arreglo: `datos_fields`, copia de `datos->'fields'` en la propia fila. Dueño único: el trigger
-- `zz_contrato_datos_fields` la recalcula en CADA insert/update desde `new.datos`, así que no puede
-- divergir, y lo que mande cualquier cliente en esa columna se ignora. Va por trigger y no como columna
-- generada: una pantalla que reenvíe la fila entera fallaría contra una generada. Se llama `zz_…` para
-- dispararse la última de los BEFORE (orden alfabético), detrás de los que reescriben `datos`
-- (trg_espejo_comprador, trg_contrato_cuenta_es_escrow).

alter table public.contratos add column if not exists datos_fields jsonb;
comment on column public.contratos.datos_fields is
  'Copia de datos->''fields'' que mantiene el trigger zz_contrato_datos_fields. Solo lectura: no escribir.';

create or replace function public._contrato_datos_fields() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.datos_fields := new.datos -> 'fields';
  return new;
end $$;
revoke all on function public._contrato_datos_fields() from public, anon, authenticated;
create trigger zz_contrato_datos_fields before insert or update on public.contratos
  for each row execute function public._contrato_datos_fields();

-- Relleno sin disparar los triggers de negocio (firma, log de eventos, vencimientos…): solo esta sesión.
set local session_replication_role = replica;
update public.contratos set datos_fields = datos -> 'fields' where datos_fields is distinct from datos -> 'fields';
set local session_replication_role = origin;

create or replace view public.documentos_desactualizados with (security_invoker = true) as
 select 'contrato'::text as tipo, c.id, c.numero, coalesce(c.bloqueado, false) as congelado,
    cl.id as client_id, cl.full_name as ficha,
    public.diferencias_con_ficha(
      jsonb_build_object('nombre', c.datos_fields ->> 'adq1_nombre', 'identidad', c.datos_fields ->> 'adq1_pasaporte',
                         'email', c.datos_fields ->> 'adq1_email', 'telefono', c.datos_fields ->> 'adq1_telefono',
                         'pais', c.datos_fields ->> 'adq1_nacionalidad'),
      jsonb_build_object('nombre', cl.full_name, 'identidad', cl.passport_number, 'email', cl.email,
                         'telefono', cl.phone, 'pais', cl.nationality)) as diferencias
   from public.contratos c
     join public.contrato_compradores cc on cc.contrato_id = c.id and cc.rol = 'adquiriente_1'
     join public.clients cl on cl.id = cc.client_id
union all
 select 'factura'::text as tipo, f.id, f.numero, coalesce(f.anulada, false) or coalesce(f.enviada, false) as congelado,
    cl.id as client_id, cl.full_name as ficha,
    public.diferencias_con_ficha(
      jsonb_build_object('nombre', f.cliente_nombre, 'identidad', (f.datos -> 'fields') ->> 'cliente_documento',
                         'email', (f.datos -> 'fields') ->> 'cliente_email'),
      jsonb_build_object('nombre', cl.full_name, 'identidad', cl.passport_number, 'email', cl.email)) as diferencias
   from public.facturas f
     join public.clients cl on cl.id = f.client_id;
