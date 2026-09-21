-- El REVOKE por columna de la migracion anterior fue un NO-OP, como ya estaba
-- escrito en el repo y se me paso: mientras exista el UPDATE a nivel de TABLA,
-- "revoke update (estado)" no quita nada (mismo gotcha que con facturas.numero,
-- 20260917082716). Hay que revocar el UPDATE entero y volver a concederlo
-- enumerando las columnas que si se editan.
--
-- Resultado: `estado` deja de ser escribible a pelo por authenticated y anon.
-- La unica via para cambiarlo es proyecto_cambiar_estado(), que valida el umbral
-- de venta, exige motivo escrito para saltarselo y deja rastro en
-- proyecto_eventos. No afecta a esa funcion: es SECURITY DEFINER con dueño postgres.
--
-- `anon` se queda ademas sin UPDATE de ninguna columna: no tiene ni una policy de
-- UPDATE, asi que el grant no le servia de nada y solo era superficie abierta.
--
-- NO se tocan aqui los otros grants de fabrica de esta tabla (DELETE, TRUNCATE,
-- REFERENCES, INSERT para anon): estan igual de abiertos y tambien sobran, pero
-- limpiarlos es mas ancho que este encargo y merece su propia revision. Queda
-- dicho, no arreglado a medias.

revoke update on public.proyectos from authenticated, anon;

grant update (
  nombre, activo, resort, parcela_master, parcela_master_m2, slug,
  fecha_entrega_estimada_proyecto, fecha_entrega_estimada_fijada_en,
  pct_minimo_inicio
) on public.proyectos to authenticated;;
