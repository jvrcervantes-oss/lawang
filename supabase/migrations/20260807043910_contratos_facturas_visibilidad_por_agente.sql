-- destructivo-ok: DROP POLICY + CREATE POLICY sustituye 3 policies de SELECT
-- por su version restringida, decision confirmada explicitamente por el
-- usuario tras 3 revisiones previas (Desarrollo/Infraestructura/Seguridad),
-- opcion "trabajo completo" elegida via AskUserQuestion. No borra filas,
-- solo cambia quien puede LEERLAS. Las clausulas "for update"/"using" son de
-- RLS policies, no UPDATE de datos.

-- Visibilidad por agente en Contratos y Facturas (7-ago). Documentacion se
-- deja FUERA a proposito: es documentacion compartida del proyecto, no de
-- un agente.

drop policy "agentes autenticados leen contratos" on public.contratos;
create policy "agentes leen sus contratos" on public.contratos
  for select to authenticated using (es_agente() and es_suyo(creado_por));

drop policy "agentes autenticados leen facturas" on public.facturas;
create policy "agentes leen sus facturas" on public.facturas
  for select to authenticated using (es_agente() and es_suyo(creado_por));

drop policy "agentes autenticados gestionan firmas" on public.contrato_firmas;
create policy "agentes gestionan firmas (escritura)" on public.contrato_firmas
  for insert to authenticated with check (es_agente());
create policy "agentes actualizan firmas" on public.contrato_firmas
  for update to authenticated using (es_agente()) with check (es_agente());
create policy "agentes borran firmas" on public.contrato_firmas
  for delete to authenticated using (es_agente());
create policy "agentes leen firmas de sus contratos" on public.contrato_firmas
  for select to authenticated using (
    es_agente() and exists (
      select 1 from public.contratos c
      where c.id = contrato_firmas.contrato_id and es_suyo(c.creado_por)
    )
  );

create or replace function public.contratos_equipo()
returns setof public.contratos
language sql security definer set search_path = ''
as $$ select * from public.contratos where public.es_agente(); $$;

create or replace function public.facturas_equipo()
returns setof public.facturas
language sql security definer set search_path = ''
as $$ select * from public.facturas where public.es_agente(); $$;

create or replace function public.contrato_firmas_equipo()
returns setof public.contrato_firmas
language sql security definer set search_path = ''
as $$ select * from public.contrato_firmas where public.es_agente(); $$;

revoke all on function public.contratos_equipo() from public;
revoke all on function public.facturas_equipo() from public;
revoke all on function public.contrato_firmas_equipo() from public;
grant execute on function public.contratos_equipo() to authenticated;
grant execute on function public.facturas_equipo() to authenticated;
grant execute on function public.contrato_firmas_equipo() to authenticated;
;
