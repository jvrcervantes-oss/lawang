-- ═══════════════════════════════════════════════════════════════════════════
-- ARCHIVAR UN TIPO DE CONTRATO — 14-sep-2026
-- ═══════════════════════════════════════════════════════════════════════════
-- Owner: «permíteme archivar contratos, unifica cuentas bancarias con esa nueva
-- función así puedo quitar morralla que no usemos. Lo que archive no debe salir
-- en la lista de crear contratos».
--
-- `plantillas_pago` nació esta misma tarde con las OCHO plantillas que cobran
-- (las que traen <!--datos-bancarios-->). Para archivar hace falta el catálogo
-- COMPLETO —20 plantillas—, así que la tabla pasa a ser el catálogo y `cobra`
-- distingue a las ocho. Se renombra porque un nombre que miente sobre lo que
-- guarda es la clase de detalle que hace que alguien lea mal una consulta.
alter table public.plantillas_pago rename to plantillas_contrato;

alter table public.plantillas_contrato
  -- `cobra`: pinta selector de cuenta de cobro (las 8 con <!--datos-bancarios-->).
  -- Las otras 12 salen en el panel con su uso y su interruptor, pero su ficha
  -- dice «este documento no cobra» en vez de una matriz de cuentas vacía.
  add column if not exists cobra     boolean not null default false,
  -- `archivada`: no se ofrece al CREAR. Nunca se borra la fila — `plantilla_cuentas`
  -- cuelga de aquí con ON DELETE CASCADE, así que borrar una plantilla archivada
  -- se llevaría por delante su reparto de cuentas sin decir nada.
  add column if not exists archivada boolean not null default false;

-- Las ocho que ya estaban en la tabla son, por definición, las que cobran.
update public.plantillas_contrato set cobra = true
 where slug in ('carta_reserva','carta_reserva_ampliada','carta_reserva_hak_sewa',
                'carta_reserva_pma','ppjb_parcela','ppjb_reserva',
                'ppjb_construccion','cc00014_timon');

-- Las 12 restantes del catálogo de `contracts/app.html`. `archivada = false`
-- para todas a propósito: qué es morralla lo decide el owner con el uso delante,
-- no esta migración.
insert into public.plantillas_contrato (slug, nombre, orden, cobra) values
  ('carta_reserva_investor_deck', 'Carta de Reserva (Investor Deck)',         45, false),
  ('hak_sewa_notario',            'Hak Sewa - Notario',                       90, false),
  ('poa_notario',                 'Poder Notarial',                          100, false),
  ('commercial_offer',            'Oferta Comercial (Apéndice D)',           110, false),
  ('commercial_collaboration',    'Acuerdo Comercial',                       120, false),
  ('colaborador_operativo',       'Protocolo Operativo (Colaborador)',       130, false),
  ('estatutos_sw',                'Estatutos SandalWoods Beachfront',        140, false),
  ('ppjb_bonian',                 'PPJB Bonian Beach',                       150, false),
  ('ppjb_bonian_c2',              'PPJB Bonian Beach · Parcela C2',          160, false),
  ('anexo_x_bonian_c2',           'Anexo X · Planos y Especificaciones (Bonian C2)', 170, false),
  ('anexo_y_bonian_c2',           'Anexo Y · Cronograma de Pagos (Bonian C2)',       180, false),
  ('adenda',                      'Adenda a contrato',                       190, false)
on conflict (slug) do nothing;

-- ── VISTA DE COMPATIBILIDAD, y por qué no es opcional ───────────────────────
-- Producción sirve AHORA un `entities.js` que consulta `plantillas_pago`. Entre
-- esta migración y el despliegue del frontend nuevo, `cargarPlantillaCuentas`
-- lanzaría y `bankOptionsFor` degradaría a ofrecer TODAS las cuentas: la Carta
-- de Reserva volvería a enseñar quince, que es exactamente lo que el trabajo de
-- esta mañana quitó. Con el webhook sano son dos minutos; con un atasco como el
-- de LAW-205, días.
--
-- `security_invoker` se pone AL CREAR y esta vista no se toca nunca con
-- `create or replace`: eso resetea la propiedad en silencio y ya ha mordido tres
-- veces en este proyecto (`unidades_estado`, 10-ago / 2-sep / 11-sep).
-- Sin grant a `anon`: mismo criterio que la tabla.
create view public.plantillas_pago with (security_invoker = true) as
  select slug, nombre, orden from public.plantillas_contrato;
revoke all on public.plantillas_pago from anon;
grant select on public.plantillas_pago to authenticated;

comment on view public.plantillas_pago is
  'PUENTE TEMPORAL (14-sep-2026): la tabla pasó a llamarse plantillas_contrato. Existe solo para que el entities.js ya desplegado no se quede sin catálogo mientras Hostinger publica el nuevo. Se tira en cuanto producción sirva la versión que consulta la tabla — ver el pendiente de esa fecha.';;
