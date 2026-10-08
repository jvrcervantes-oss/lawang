-- Reversion de la migracion 20261010030000 (E9 · contrato nuevo creado por el cliente, 8-oct-2026).
-- Quita la RPC y su ayudante, devuelve el validador de bloqueos a su definicion anterior, la politica de lectura a «USING true» y suelta las 3 columnas nuevas de plantillas_contrato.
-- GUARDA: aborta si existe algun contrato propio de una empresa (plantillas_contrato.empresa no nulo): borrarlo destruiria sus versiones; retiralo o exportalo antes.
-- destructivo-ok: aborta antes si hay contratos propios; si no hay, solo suelta columnas/indice/constraints vacios y restituye funciones y politica
begin;

do $g$
declare n int;
begin
  select count(*) into n from public.plantillas_contrato where empresa is not null;
  if n > 0 then
    raise exception 'REVERSION ABORTADA: hay % contrato(s) propio(s) de empresa. Exportalos antes.', n using errcode = '55000';
  end if;
end $g$;

drop trigger plantilla_version_empresa_propia on public.plantilla_contrato_versiones;
drop function public._trg_plantilla_version_empresa_propia();
drop function public.plantilla_contrato_nuevo_crea(text, text, text, text, uuid, jsonb);
drop function public._plantilla_esqueleto_en_blanco(text, text[], text);

create or replace function public._plantilla_motivo_bloqueo(p_cuerpo text, p_empresa text, p_slug text) returns text
 language plpgsql stable security definer set search_path = '' as $$
declare m text[] := '{}'; x text; h text[];
begin
  select n.motivo into x from public.plantilla_nunca_activable n where n.empresa = p_empresa and n.slug = p_slug;
  if x is not null then m := m || x; end if;
  if p_slug = 'estatutos_sw' and not exists (select 1 from public.plantilla_ficha f where f.empresa = p_empresa and f.clave = 'promotora_razon' and nullif(btrim(f.valor), '') is not null) then
    m := m || 'Falta la razon social juridica de la promotora fundadora (promotora_razon): la da el owner, no se rellena con algo plausible'::text;
  end if;
  h := public._plantilla_otra_sociedad(p_cuerpo, p_empresa);
  if cardinality(h) > 0 then m := m || ('El texto nombra a otra sociedad (' || array_to_string(h, ', ') || '): usa los marcadores de la sociedad de la empresa'); end if;
  return nullif(array_to_string(m, ' | '), '');
end $$;

drop policy "plantillas de contrato: del estudio o de mi empresa" on public.plantillas_contrato;
create policy "plantillas de pago: solo con sesion" on public.plantillas_contrato for select to authenticated, lw_lector using (true);

drop index public.plantillas_contrato_nombre_empresa;
alter table public.plantillas_contrato
  drop constraint plantillas_contrato_propia_slug, drop constraint plantillas_contrato_propia_campos, drop constraint plantillas_contrato_propia_nombre;
alter table public.plantillas_contrato drop column empresa, drop column campos, drop column creada_por;

commit;
