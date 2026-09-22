-- destructivo-ok: DROP TRIGGER if exists es el patron estandar del repo para
-- reemplazar un trigger por su propia version (mismo nombre). No borra filas.
--
-- Hallazgo ALTA de Seguridad en la consulta de deploy de la migracion anterior
-- (20260922131500_facturas_congela_contrato_numero): la funcion del trigger era
-- SECURITY DEFINER y leia contratos.numero para CUALQUIER contrato_id que el
-- propio INSERT/UPDATE de facturas trajera, sin comprobar que el agente puede
-- ver ese contrato. Verificado antes de tocar nada (pg_policy real):
--   - facturas, INSERT (with check): solo `es_agente() and puede('facturas')`
--     -- NO acota que contrato_id pertenezca al agente.
--   - contratos, SELECT: `es_agente() and (es_suyo(creado_por) or
--     es_manager_de(proyecto_id))` -- SI acota.
-- Con DEFINER, el trigger se saltaba esa segunda policy: un agente podia crear
-- una factura suya con el contrato_id de un contrato ajeno (de otro agente o
-- proyecto) y el trigger le congelaba en su propia fila el numero real de ese
-- contrato -- un oraculo de lectura no autorizada (mismo patron que el ya
-- detectado en RWA admin_users).
--
-- Fix: quitar SECURITY DEFINER. Sin ella, el SELECT sobre contratos corre con
-- los privilegios de quien invoca (authenticated ya tiene GRANT SELECT en la
-- tabla -- verificado, así que no rompe el caso normal) y queda sujeto a la
-- misma policy "agentes leen sus contratos" que ya es la fuente única de quién
-- puede ver qué contrato: si el agente no puede verlo, el SELECT no devuelve
-- fila y contrato_numero se queda NULL -- ni error, ni fuga, ni logica
-- duplicada de permisos dentro del trigger.
create or replace function public._facturas_congela_contrato_numero()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.contrato_id is not null and new.contrato_numero is null then
    select c.numero into new.contrato_numero
      from public.contratos c
     where c.id = new.contrato_id;
  end if;
  return new;
end;
$$;

comment on function public._facturas_congela_contrato_numero() is
  'Congela contrato_numero desde contratos.numero en cuanto una factura recibe un contrato_id, si no llega ya puesto. SECURITY INVOKER a proposito (fix 22-sep-2026): el SELECT queda sujeto a la policy de lectura de contratos del propio agente, para no filtrar el numero de un contrato ajeno via un contrato_id que la policy de INSERT de facturas no acota. Nunca pisa un valor ya presente ni actua cuando contrato_id se vacia.';

drop trigger if exists trg_facturas_congela_contrato_numero on public.facturas;
create trigger trg_facturas_congela_contrato_numero
  before insert or update on public.facturas
  for each row execute function public._facturas_congela_contrato_numero();

revoke all on function public._facturas_congela_contrato_numero() from public, anon, authenticated;
