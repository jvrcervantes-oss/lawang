-- Auditoría de Seguridad 25-sep-2026 — dos endurecimientos, ninguno cambia lo que ve el equipo.
--
-- 1) `unidades_borradas` y `proyectos_borrados` se leían con `using (true)` para
--    cualquier `authenticated`. Desde el portal de autoservicio (8-sep) eso incluye
--    a los compradores (29 cuentas a 25-sep), que así podían pedir por REST los
--    precios de unidades borradas y el email de quien las borró. El portal no usa
--    ninguna de las dos (grep de `portal/` y `contracts/assets/`); solo la intranet.
--    Pasan a `es_agente()`, el mismo candado que el resto de tablas del equipo.
--    Las demás `using (true)` (`cuentas_bancarias`, `sociedades`, `plantillas_contrato`,
--    `plantilla_cuentas`, `proyecto_cuentas`, `mantenimiento`) NO se tocan: el portal
--    las carga para componer las facturas del comprador (`portal/index.html`, carga).
--
-- 2) `search_path` fijo en las 3 funciones que el advisor marca como mutables
--    (lint 0011). Son SECURITY INVOKER, así que el riesgo era bajo; `public, pg_temp`
--    resuelve los nombres sin calificar exactamente igual que hoy.

alter policy "unidades borradas: solo con sesion" on public.unidades_borradas
  using (public.es_agente());
alter policy "proyectos borrados: solo con sesion" on public.proyectos_borrados
  using (public.es_agente());

alter function public.lw_importe(text)            set search_path = public, pg_temp;
alter function public.lw_importe_texto(numeric)   set search_path = public, pg_temp;
alter function public.unidad_precio_es_la_suma()  set search_path = public, pg_temp;
