-- POR APLICAR, NO APLICADO (13-oct-2026). Retira cliente_traspasa del navegador cuando ya no le quede llamador publicado.
--
-- Por que existe: desde la migracion 20261013143832_traspaso_cliente_arrastra_todo el traspaso SIEMPRE arrastra contratos y facturas, y la pantalla
--   nueva (intranet/v4/assets/datos.js, cajon de clientes) llama solo a traspasar_cliente_con_documentos. cliente_traspasa quedo como envoltorio
--   para la pantalla VIEJA mientras siga publicada. Regla «reducir la exposicion» (contexto/seguridad_2026.md §1.ter): sin llamador, se revoca.
--
-- Cuando se aplica EN LAWANG (esta base es solo de Lawang; las instancias del ERP tienen su base y su propia retirada). Las tres, comprobadas:
--   1. La copia sesion/1013-2205-traspaso-arrastra ha aterrizado y el datos.js NUEVO es el que se sirve: el ?v= de datos.js en
--      https://<intranet>/intranet/v4/compradores/index.html es el de main, y curl -s "https://<intranet>/intranet/v4/assets/datos.js?v=<ese sello>"
--      | grep -c "cliente_traspasa" da 0.
--   2. git grep -n "cliente_traspasa" en proyectos/Lawang con main al dia, fuera de supabase y contracts/sql: nada (la intranet clasica se
--      archivo en 7570f837c; si reaparece un llamador, no se aplica).
--   3. Nadie la ha llamado desde el aterrizaje: los logs de la API (query_logs, servicio api) sin «/rpc/cliente_traspasa» en las 24 h siguientes
--      (una pestana abierta con el datos.js viejo la seguiria llamando hasta recargar).
--   Las instancias del ERP (erp/despliegues/<inst>, demo-erp) llevan su propio revoke en su base: no se miran aqui.
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
