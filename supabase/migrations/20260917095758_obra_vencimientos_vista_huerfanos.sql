-- Contratos de Construccion firmados sin unidad_id: quedarian fuera, en silencio,
-- del mecanismo de vencimientos por avance de obra (que agrupa por unidad->fase-zona).
-- encargos/20260917_lawang_vencimientos_obra.md
create or replace view public.contratos_construccion_sin_unidad
with (security_invoker = true) as
select c.id, c.numero, c.proyecto_nombre,
       c.datos->'fields'->>'ubicacion_proyecto' as ubicacion_proyecto_declarada,
       c.datos->'fields'->>'num_reserva_vinculada' as num_reserva_vinculada_declarada,
       c.contrato_padre_id
from public.contratos c
where c.tipo = 'construccion' and c.bloqueado = true and c.unidad_id is null;

revoke all on public.contratos_construccion_sin_unidad from public, anon, authenticated;
grant select on public.contratos_construccion_sin_unidad to authenticated;

comment on view public.contratos_construccion_sin_unidad is
  'Contratos de Construccion firmados sin unidad_id -- quedan fuera del mecanismo de vencimientos por obra hasta que alguien confirme la parcela real. 17-sep-2026: CC00006 y CC00020 son casos genuinos (la parcela que declaran ya pertenece a otra reserva, sin cadena de contrato_padre_id que lo explique) -- no resolver por texto, requieren revision humana.';
