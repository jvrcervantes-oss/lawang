-- Recibís/facturas: la lectura también sigue al CONTRATO (24-sep-2026).
--
-- Síntoma (owner): «no se cargan los recibís de la Carta de Reserva en algunos
-- proyectos en v4». Causa: la policy de SELECT de `facturas` miraba autor y
-- proyecto DEL DOCUMENTO (`es_suyo(creado_por) OR es_manager_de(proyecto_id)`),
-- mientras lo cobrado (`contratos_cobrado_equipo`, DEFINER) y el propio contrato
-- siguen al CONTRATO (`contrato_visible`). Cuando el recibí lo emite otra
-- persona (admin, finanzas, el project manager) sobre el contrato de un sales
-- manager que no supervisa ese proyecto, el dueño del contrato veía «Cobrado
-- 77.600 €» y cero recibís. Reproducido como `sales` sobre RP00017/RP00040
-- (Bonian): contratos 2, cobrado 77.600, recibís 0. 10 recibís de reserva
-- afectados hoy (Bonian, Soka, Sumba Hills, Tamarind).
--
-- Arreglo: un documento es legible si ya lo era O si su contrato es visible
-- para quien lee — mismo criterio que `contrato_firmas` y `contrato_cobrado`.
-- Solo LECTURA: editar/anular/borrar sigue siendo del autor, su manager o admin.
-- Se aplica igual a `recibi_aplicaciones` y a los justificantes del bucket,
-- para que la ficha no enseñe un recibí sin su «salda a» ni su justificante.

create or replace function public.documento_visible(p_autor text, p_proyecto_id uuid, p_contrato_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.es_suyo(p_autor)
      or public.es_manager_de(p_proyecto_id)
      or (p_contrato_id is not null and exists (
            select 1 from public.contratos c
             where c.id = p_contrato_id
               and public.contrato_visible(c.creado_por, c.proyecto_id)))
$$;

revoke all on function public.documento_visible(text, uuid, uuid) from public, anon;
grant execute on function public.documento_visible(text, uuid, uuid) to authenticated;

alter policy "agentes leen sus facturas" on public.facturas
  using (public.es_agente() and public.documento_visible(creado_por, proyecto_id, contrato_id));

alter policy "agentes leen aplicaciones de sus documentos" on public.recibi_aplicaciones
  using (public.es_agente() and exists (
    select 1 from public.facturas d
     where d.id in (recibi_aplicaciones.recibi_id, recibi_aplicaciones.factura_id)
       and public.documento_visible(d.creado_por, d.proyecto_id, d.contrato_id)));

create or replace function public.agente_ve_justificante(p_name text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.es_agente() and exists (
    select 1
      from public.facturas f
     where (f.justificante_path = p_name
            or exists (select 1
                         from jsonb_array_elements(coalesce(f.justificantes, '[]'::jsonb)) e
                        where e ->> 'path' = p_name))
       and public.documento_visible(f.creado_por, f.proyecto_id, f.contrato_id))
$$;
