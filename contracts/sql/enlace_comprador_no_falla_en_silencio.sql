-- ════════════════════════════════════════════════════════════════════════════
-- EL ENLACE DEL COMPRADOR DEJÓ DE HACERSE, Y NADIE LO VIO — 19-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- SÍNTOMA: los 7 contratos creados hoy (RP00053-58 y CR00035) traían su
-- `datos.adq1_client_id` pero NO tenían fila en `contrato_compradores`. Todos
-- los de ayer sí. O sea: el enlace se rompió en algún momento de la madrugada.
--
-- CAUSA, y es una regresión de la propia auditoría de esta mañana. El hallazgo
-- decía: «`sincronizar_compradores` tiene EXECUTE para anon — una definer que
-- escribe, invocable sin sesión por REST». Cierto y bien cazado. Pero el
-- arreglo fue `revoke all ... from public, anon`, y **el EXECUTE que usaba
-- `authenticated` venía justamente por PUBLIC**. Desde entonces:
--
--   guardar contrato → trg_compradores_desde_datos (INVOKER)
--                    → public.sincronizar_compradores(...)  ← permission denied
--                    → el handler lo convierte en RAISE WARNING
--                    → el contrato se guarda igual, sin enlace, sin ruido
--
-- El WARNING va al log del servidor, que no mira nadie. Es la forma más cara de
-- fallar: todo parece funcionar.
--
-- ARREGLO: no reabrir la función —eso deshace la auditoría—, sino que el
-- TRIGGER sea `security definer`. Así la llamada corre como su dueño (postgres)
-- y REST sigue cerrado para anon Y para authenticated, que era el objetivo.
create or replace function public.trg_sincronizar_compradores()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform public.sincronizar_compradores(new.id);
  exception when others then
    raise warning 'sincronizar_compradores(%) no pudo completarse: %', new.id, sqlerrm;
  end;
  return new;
end $$;

revoke all on function public.trg_sincronizar_compradores() from public, anon, authenticated;

-- ── recuperación de lo que se perdió ───────────────────────────────────────
-- No se inventa nada: `sincronizar_compradores` solo RECONOCE fichas, nunca
-- crea personas (ver comprador_desde_ficha.sql). Los 7 contratos recuperaron su
-- enlace (RP00055 y RP00058 dos cada uno, por sus adquirientes adicionales) y
-- después quedaron 0 contratos con ficha y sin enlazar.
--
--   select c.numero, public.sincronizar_compradores(c.id)
--     from public.contratos c
--    where c.datos->>'adq1_client_id' is not null
--      and not exists (select 1 from public.contrato_compradores cc
--                       where cc.contrato_id = c.id);
--
-- ── y para que no vuelva a ser silencioso ──────────────────────────────────
-- `informarCompradores()` en app.html YA avisaba de esto… con un `toast`, que
-- es lo que se perdió entre los otros dos que salen al guardar. Desde hoy es un
-- modal: un aviso que se puede no ver no es un aviso.
--
-- LECCIÓN, y es la tercera vez que este estudio la escribe de otra forma: **un
-- GRANT no restringe, añade — y un REVOKE sobre PUBLIC quita el permiso a todo
-- el que solo lo tenía por ahí**. Al cerrar una función a `anon`, comprobar
-- ANTES quién más la estaba usando y por qué camino:
--   select proacl from pg_proc where proname = '...';
--   select has_function_privilege('authenticated', oid, 'execute') ...
