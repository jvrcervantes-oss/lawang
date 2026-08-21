-- Tres policies de LAW-71 nacieron `TO PUBLIC` — 21-ago-2026.
--
-- Al escribirlas sin cláusula `to`, Postgres las aplica al rol `public`, o sea
-- también a `anon`. No es una fuga: lo que decide es el USING, y ahí llaman a
-- `es_super_admin()` / `es_agente()`, que `anon` NO puede ejecutar (se le revocó
-- el 29-jul). Pero eso significa que para un cliente sin sesión la policy no
-- devuelve «false», sino un ERROR de permisos sobre la función — el mismo modo
-- de fallo que ya costó un rato el 19-ago con `sincronizar_compradores`, donde
-- un permiso que faltaba salía como un mensaje que no hablaba de permisos.
--
-- Se acotan a `authenticated`, que es el estilo del resto de la suite. Para
-- quien usa la herramienta no cambia NADA: son los mismos predicados sobre los
-- mismos roles. Lo que desaparece es el camino de error para `anon`, que ahora
-- simplemente no encuentra policy y no puede.
--
-- `service_role` no se ve afectado: salta la RLS entera por definición, así que
-- la edge de firma sigue igual.
--
-- Verificado antes de tocar: ninguna policy de `contratos` o `facturas` deja
-- leer a `anon` (la de julio «anon puede leer contratos» ya no existe), y las
-- cuatro vistas del esquema son `security_invoker=true`, o sea que ninguna se
-- salta la RLS de sus tablas.

drop policy if exists "super admin lee borrados" on public.borrados;
create policy "super admin lee borrados" on public.borrados
  for select to authenticated
  using (public.es_super_admin());

drop policy if exists "el autor o un admin editan contratos no bloqueados" on public.contratos;
create policy "el autor o un admin editan contratos no bloqueados" on public.contratos
  for update to authenticated
  using (
    public.es_super_admin()
    or (bloqueado = false and public.es_agente() and public.puede('contratos')
        and public.es_suyo(creado_por) and public.puede_proyecto_de(datos, proyecto_nombre))
  )
  with check (
    public.es_super_admin()
    or (public.es_agente() and public.puede('contratos')
        and public.puede_proyecto_de(datos, proyecto_nombre))
  );;
