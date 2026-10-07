-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2B · migracion 1 (7-oct-2026): CUENTAS DE COBRO POR EMPRESA (F2d).
--   cuentas_bancarias gana `empresa` (null = tercero/escrow/otra sociedad: lo ven todos, como hoy). Solo se rellena donde el titular es inequivoco:
--   PT SAN DAL WOODS -> sandal_woods; PT Tepi Sun Gai -> lawang. Las demas (Sandal Woods Limited HK/SG/Lux, notarios, terreno, constructores) quedan null y se anotan para el owner.
--   Un rol de empresa (o un usuario con empresas marcadas) NO ve la cuenta propia de la otra empresa, ni por la funcion ni por la policy directa. Los 34 de hoy (empresas vacias): sin cambio.
--   Dos wrappers con EXECUTE (los llaman policies): empresa_en_alcance(text) y sociedad_en_alcance(text). Leccion G1: una policy que llama a una funcion sin EXECUTE rompe todas las lecturas.
-- destructivo-ok: add column nullable, dos funciones nuevas, create or replace de una funcion, alter policy; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2b.sql
alter table public.cuentas_bancarias add column if not exists empresa text references public.empresas(clave);
update public.cuentas_bancarias set empresa = 'sandal_woods' where clave = 'sandalwoods_danamon_eur' and empresa is null;
update public.cuentas_bancarias set empresa = 'lawang' where clave = 'contractor_tepisungai' and empresa is null;

create or replace function public.empresa_en_alcance(p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_empresa is null or public._ve_empresa(p_empresa)
$$;
create or replace function public.sociedad_en_alcance(p_sociedad text) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from public.empresas e
                      where e.sociedad_clave = p_sociedad and not public._ve_empresa(e.clave))
$$;
revoke all on function public.empresa_en_alcance(text), public.sociedad_en_alcance(text) from public, anon;
grant execute on function public.empresa_en_alcance(text), public.sociedad_en_alcance(text) to authenticated, lw_lector;

alter policy "cuentas: agentes" on public.cuentas_bancarias
  using (public.es_agente() and public.empresa_en_alcance(empresa));

create or replace function public.cuentas_cobro_visibles()
 returns table(clave text, label text, titular text, banco text, cuenta text, codigo text, direccion text, extra jsonb, es_escrow boolean, orden integer)
 language sql stable security definer set search_path = '' as $$
  select c.clave, c.label, c.titular, c.banco, c.cuenta, c.codigo, c.direccion, c.extra, c.es_escrow, c.orden
    from public.cuentas_bancarias c
   where c.activa and (
         (public.es_agente() and public.empresa_en_alcance(c.empresa))
      or (public.es_portal() and c.clave in (
            select f.datos->'fields'->>'cuenta'
              from public.facturas f
              join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
              join public.portal_accesos pa on pa.client_id = cc.client_id and pa.activo
                                            and pa.email = lower(coalesce((select auth.email()), ''))
             where not coalesce(f.anulada, false))))
   order by c.orden $$;
