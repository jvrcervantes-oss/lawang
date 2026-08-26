-- Qué tipos de contrato puede EMITIR cada persona. 27-ago-2026, encargo del owner:
-- «al igual que desde el panel de usuarios puedo hacer que vean los agentes
-- también quiero seleccionar que tipos de contrato pueden hacer».
--
-- 🔴 VACÍO = SIN RESTRICCIÓN, no «ninguno». Y eso es DISTINTO de `proyectos`,
-- donde vacío sí significa ninguno. El motivo es que esto se añade sobre un
-- sistema que ya funciona: si vacío significara «ninguno», este ALTER dejaría
-- a los 10 agentes sin poder emitir un solo contrato en el momento del despliegue,
-- sin que nadie lo hubiera pedido. Una restricción nueva empieza sin restringir.
-- El panel lo dice con todas las letras donde se marca, que es donde importa.
alter table public.usuarios
  add column if not exists tipos_contrato text[] not null default '{}';

comment on column public.usuarios.tipos_contrato is
  'Tipos de contrato que esta persona puede emitir. Array VACÍO = todos (sin restricción), a diferencia de `proyectos`, donde vacío = ninguno. Se comprueba en el trigger `contratos_tipo_permitido`, no solo en el navegador.';
