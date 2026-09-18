-- ============================================================================
-- Storage deja de ser una carpeta compartida. 18-sep-2026.
--
-- POR QUE. Las politicas de LECTURA de `kyc`, `contratos-firmados`,
-- `justificantes` y `documentacion` eran `es_agente()` a secas, y `es_agente()`
-- es literalmente «existe en `public.usuarios` y esta activo»: sin proyecto, sin
-- autor, sin dueño. Cualquier usuario del ERP podia hacer `storage.list` y
-- descargarse los 188 documentos de KYC (pasaporte y NIK de compradores
-- reales), los 113 PDF de contratos firmados y los 119 justificantes de pago,
-- fueran suyos o no. La RLS de las TABLAS estaba bien; el bucket no la mira.
--
-- Hallazgo de Seguridad en la revision previa del 18-sep-2026 del encargo de
-- multiempresa (`encargos/20260918_lawang_multiempresa_karana.md`), verificado
-- contra `pg_policy` de `storage.objects`. Se arregla AHORA y no dentro de ese
-- encargo porque el agujero esta abierto hoy, con un solo cliente dentro.
--
-- COMO. El patron ya existe y funciona en este mismo proyecto para el portal
-- del comprador (`portal_ve_pdf(name)`): el objeto se resuelve contra SU FILA y
-- se aplica la visibilidad que ya tiene esa fila. Se replica para el equipo. NO
-- se re-prefijan las rutas con el proyecto ni el dueño: obligaria a mover cada
-- objeto ya subido, y una migracion de objetos no es un arreglo de seguridad.
--
-- MEDIDO ANTES DE TOCAR, en produccion:
--   · `kyc` 188 objetos, 0 huerfanos: los 188 casan con `documents.storage_path`.
--   · `documentacion` 2 objetos, 0 huerfanos.
--   · `contratos-firmados` 113: 76 en la raiz (11 sin contrato que los reclame)
--     y 37 en `pendientes/` (36 casan con el id del contrato en el nombre).
--   · `justificantes` 119, de los que 28 no los reclama ninguna factura.
--   Los huerfanos (11 + 28 + 1) quedan accesibles SOLO para admin, por eso cada
--   politica lleva `es_admin() or ...`: nadie pierde un fichero, deja de verlo
--   quien no tiene nada que ver con el.
--
-- LO QUE NO HACE, a proposito: no toca INSERT/UPDATE/DELETE. Subir es lo
-- primero que pasa —el objeto existe ANTES de que exista la fila que lo
-- reclama—, asi que cerrar la escritura con la misma regla romperia las altas.
-- Se cierra el leer, que es por donde se sale el dato; el escribir queda anotado
-- en el encargo con su motivo. Tampoco toca `modelos` (5 renders de catalogo,
-- sin dato personal) ni `obra`, que ya esta gobernada por `puede('obra')`.
--
-- destructivo-ok: los unicos DROP son `drop policy` + `create policy` de la
-- misma politica de lectura, para sustituir `es_agente()` por la resolucion
-- contra su fila. No se borra ni un objeto ni una fila, y las cuatro politicas
-- quedan estrictamente mas restrictivas. Aprobado por el owner el 18-sep-2026
-- al pedir la Fase 0 entera.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Quien ve que. Cada funcion resuelve el objeto contra su fila y delega la
-- decision en la visibilidad que esa fila YA tiene: nada de reglas nuevas.
-- ---------------------------------------------------------------------------
create or replace function public.agente_ve_kyc(p_name text)
returns boolean language sql stable security definer set search_path to ''
as $$
  select public.es_agente() and exists (
    select 1
      from public.documents d
      join public.clients c on c.id = d.client_id
     where d.storage_path = p_name
       and public.cliente_visible(c.propietario, c.id))
$$;

create or replace function public.agente_ve_contrato_pdf(p_name text)
returns boolean language sql stable security definer set search_path to ''
as $$
  select public.es_agente() and exists (
    select 1
      from public.contratos c
     where (c.pdf_firmado_path = p_name
            -- `pendientes/<id del contrato>.html`: el borrador que se congela
            -- mientras el contrato esta en firma. Es el MISMO contenido que el
            -- PDF final, asi que se gobierna igual; dejarlo abierto seria dejar
            -- la puerta de al lado sin cerrar.
            or (p_name like 'pendientes/%'
                and c.id::text = replace(replace(p_name, 'pendientes/', ''), '.html', '')))
       and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id)))
$$;

create or replace function public.agente_ve_justificante(p_name text)
returns boolean language sql stable security definer set search_path to ''
as $$
  select public.es_agente() and exists (
    select 1
      from public.facturas f
     where (f.justificante_path = p_name
            or exists (select 1
                         from jsonb_array_elements(coalesce(f.justificantes, '[]'::jsonb)) e
                        where e ->> 'path' = p_name))
       and (public.es_suyo(f.creado_por) or public.es_manager_de(f.proyecto_id)))
$$;

create or replace function public.agente_ve_documento_proyecto(p_name text)
returns boolean language sql stable security definer set search_path to ''
as $$
  select public.es_agente() and exists (
    select 1
      from public.documentos_proyecto dp
     where dp.path = p_name
       and public.puede_proyecto(dp.proyecto, dp.proyecto_id))
$$;

grant execute on function public.agente_ve_kyc(text)                to authenticated;
grant execute on function public.agente_ve_contrato_pdf(text)       to authenticated;
grant execute on function public.agente_ve_justificante(text)       to authenticated;
grant execute on function public.agente_ve_documento_proyecto(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Las cuatro politicas de lectura. Se conserva intacta la del portal, que ya
-- resolvia bien.
-- ---------------------------------------------------------------------------
drop policy if exists "agentes leen kyc" on storage.objects;
create policy "agentes leen kyc"
  on storage.objects for select to authenticated
  using (bucket_id = 'kyc' and (public.es_admin() or public.agente_ve_kyc(name)));

drop policy if exists "agentes autenticados leen pdf firmado" on storage.objects;
create policy "agentes autenticados leen pdf firmado"
  on storage.objects for select to authenticated
  using (bucket_id = 'contratos-firmados'
         and (public.es_admin() or public.agente_ve_contrato_pdf(name)));

drop policy if exists "agentes leen justificantes" on storage.objects;
create policy "agentes leen justificantes"
  on storage.objects for select to authenticated
  using (bucket_id = 'justificantes'
         and (public.es_admin() or public.agente_ve_justificante(name)));

drop policy if exists "documentacion: agentes leen" on storage.objects;
create policy "documentacion: agentes leen"
  on storage.objects for select to authenticated
  using (bucket_id = 'documentacion'
         and (public.es_admin() or public.agente_ve_documento_proyecto(name)));
