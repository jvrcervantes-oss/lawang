-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2B · migracion 2 (7-oct-2026): SOCIEDADES POR EMPRESA. Una sociedad ligada a una empresa (tepi_sungai<->lawang, san_dal_woods<->sandal_woods) solo la ve quien ve esa empresa;
--   las demas (sociedades sin empresa) siguen visibles para todo agente. Policy directa y funcion. Los 34 de hoy: sin cambio.
-- destructivo-ok: alter policy y create or replace de una funcion; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2b.sql
alter policy "sociedades: agentes" on public.sociedades
  using (public.es_agente() and public.sociedad_en_alcance(clave));

create or replace function public.sociedades_visibles()
 returns table(clave text, label text, razon text, marca text, npwp text, npwp_label text, nib text, domicilio text, rep text, logo text, logo_alto text, emisor_debajo boolean, folio text, tinta jsonb, es_indonesia boolean, orden integer)
 language sql stable security definer set search_path = '' as $$
  select s.clave, s.label, s.razon, s.marca, s.npwp, s.npwp_label, s.nib, s.domicilio, s.rep,
         s.logo, s.logo_alto, s.emisor_debajo, s.folio, s.tinta, s.es_indonesia, s.orden
    from public.sociedades s
   where s.activa and (
         (public.es_agente() and public.sociedad_en_alcance(s.clave))
      or (public.es_portal() and s.clave in (
            select x.k from public.facturas f
              join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
              join public.portal_accesos pa on pa.client_id = cc.client_id and pa.activo
                                            and pa.email = lower(coalesce((select auth.email()), ''))
              cross join lateral (values (f.sociedad), (f.datos->'fields'->>'sociedad')) x(k)
             where not coalesce(f.anulada, false))))
   order by s.orden $$;
