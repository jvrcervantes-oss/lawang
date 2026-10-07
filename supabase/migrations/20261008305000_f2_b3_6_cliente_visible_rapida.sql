-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · BLOQUE 3 · migracion 6 (7-oct-2026): cliente_visible, rama de empresa en linea.
--   La migracion 2 anadio a cliente_visible una llamada a una funcion por fila (_propietario_en_mis_empresas). Medido en transaccion (mejor de 7, un agente leyendo clients):
--   con la funcion 579 ms / 431 ms; con la misma comprobacion escrita en linea 396 ms; sin la rama 385 ms. Se deja en linea para que un agente normal no pague la rama de empresa (leccion de 2A: +250 ms en facturas).
-- destructivo-ok: create or replace de una funcion; sin tocar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b3.sql
create or replace function pg_temp.f2_edita(p_fn text, p_viejo text, p_nuevo text) returns void language plpgsql as $f$
declare d text; n int;
begin
  d := pg_get_functiondef(p_fn::regprocedure);
  n := (length(d) - length(replace(d, p_viejo, ''))) / length(p_viejo);
  if n <> 1 then raise exception 'f2_edita %: el fragmento aparece % veces (esperaba 1): %', p_fn, n, left(p_viejo, 70); end if;
  execute replace(d, p_viejo, p_nuevo);
end $f$;
select pg_temp.f2_edita('public.cliente_visible(text,uuid)',
  $v$or public._propietario_en_mis_empresas(p_propietario)$v$,
  $n$or (p_propietario is not null and exists (
            select 1 from public.usuarios me
             where me.user_id = (select auth.uid()) and me.activo and me.ambito = 'empresa'
               and me.rol in ('admin_empresa','super_admin_empresa')
               and exists (select 1 from public.usuarios pr
                            where lower(pr.email) = lower(p_propietario) and pr.activo and pr.empresas && me.empresas)))$n$);
