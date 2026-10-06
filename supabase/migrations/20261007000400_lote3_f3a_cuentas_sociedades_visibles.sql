-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 3 · F3 fase A (OK del owner 6-oct-2026). Aditiva. Investigado: el portal solo pinta FACTURAS (documento.js: CUENTAS_BANCARIAS[fields.cuenta], SOCIEDADES[fields.sociedad] + f.emisor);
--   no carga plantilla_cuentas ni proyecto_cuentas. Asi que al comprador del portal le basta con las cuentas y sociedades que citan SUS facturas (no anuladas, de sus contratos),
--   y el agente conserva todas las activas. Misma forma de filas que las consultas directas que sustituyen (entities.js cargarCuentasBancarias/cargarSociedades).
-- destructivo-ok: solo crea dos funciones; no toca filas ni policies.
-- REVERTIR: drop function public.cuentas_cobro_visibles(); drop function public.sociedades_visibles();
create or replace function public.cuentas_cobro_visibles()
returns table(clave text, label text, titular text, banco text, cuenta text, codigo text, direccion text, extra jsonb, es_escrow boolean, orden integer)
language sql stable security definer set search_path = '' as $$
  select c.clave, c.label, c.titular, c.banco, c.cuenta, c.codigo, c.direccion, c.extra, c.es_escrow, c.orden
    from public.cuentas_bancarias c
   where c.activa and (
         public.es_agente()
      or (public.es_portal() and c.clave in (
            select f.datos->'fields'->>'cuenta'
              from public.facturas f
              join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
              join public.portal_accesos pa on pa.client_id = cc.client_id and pa.activo
                                            and pa.email = lower(coalesce((select auth.email()), ''))
             where not coalesce(f.anulada, false))))
   order by c.orden $$;
revoke all on function public.cuentas_cobro_visibles() from public, anon;
grant execute on function public.cuentas_cobro_visibles() to authenticated;

create or replace function public.sociedades_visibles()
returns table(clave text, label text, razon text, marca text, npwp text, npwp_label text, nib text, domicilio text, rep text,
              logo text, logo_alto text, emisor_debajo boolean, folio text, tinta jsonb, es_indonesia boolean, orden integer)
language sql stable security definer set search_path = '' as $$
  select s.clave, s.label, s.razon, s.marca, s.npwp, s.npwp_label, s.nib, s.domicilio, s.rep,
         s.logo, s.logo_alto, s.emisor_debajo, s.folio, s.tinta, s.es_indonesia, s.orden
    from public.sociedades s
   where s.activa and (
         public.es_agente()
      or (public.es_portal() and s.clave in (
            select x.k from public.facturas f
              join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
              join public.portal_accesos pa on pa.client_id = cc.client_id and pa.activo
                                            and pa.email = lower(coalesce((select auth.email()), ''))
              cross join lateral (values (f.sociedad), (f.datos->'fields'->>'sociedad')) x(k)
             where not coalesce(f.anulada, false))))
   order by s.orden $$;
revoke all on function public.sociedades_visibles() from public, anon;
grant execute on function public.sociedades_visibles() to authenticated;
