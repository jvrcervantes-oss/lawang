-- POR APLICAR, NO APLICADO (13-oct-2026). Retira cliente_traspasa del navegador cuando ya no le quede llamador publicado.
--
-- Por que existe: desde la migracion 20261013143832_traspaso_cliente_arrastra_todo el traspaso SIEMPRE arrastra contratos y facturas, y la pantalla
--   nueva (intranet/v4/assets/datos.js, cajon de clientes) llama solo a traspasar_cliente_con_documentos. cliente_traspasa quedo como envoltorio
--   para la pantalla VIEJA mientras siga publicada. Regla «reducir la exposicion» (contexto/seguridad_2026.md §1.ter): sin llamador, se revoca.
--
-- Cuando se aplica (las tres cosas comprobadas, no supuestas):
--   1. El datos.js nuevo de Lawang esta en produccion: curl -s https://<intranet>/intranet/v4/assets/datos.js | grep -c "cliente_traspasa" → 0.
--   2. El front publicado de cada instancia del ERP (erp/despliegues/<inst>/ y AxisWorks/comercial/demo-erp/dist, dist/demo-erp) ya no la nombra:
--      grep -rl "cliente_traspasa" en esos dist → solo los mapas generados guard.js / modulos_hub.js (salen de erp/modulos.json; regenerarlos).
--   3. grep -rn "cliente_traspasa" proyectos/Lawang (sin supabase/ ni contracts/sql/) → nada.
-- Como: migracion nueva en supabase/migrations con este cuerpo (apply_migration), y despues tools/supabase_fetch_seguro.py.
-- No es destructivo (revoke, no drop): la funcion se queda para un rollback del front; volver atras = grant execute ... to authenticated.

revoke execute on function public.cliente_traspasa(uuid, text, text) from authenticated;

do $$
begin
  if has_function_privilege('authenticated', 'public.cliente_traspasa(uuid,text,text)', 'execute')
     or has_function_privilege('anon', 'public.cliente_traspasa(uuid,text,text)', 'execute') then
    raise exception 'cliente_traspasa sigue abierta al navegador';
  end if;
end $$;
