-- ═══════════════════════════════════════════════════════════════════════════
--  poder_id — bajo qué Poder Notarial actúa el apoderado del comprador
--  17-ago-2026 · APLICADO (migración poder_id_enlace_contrato_a_su_poder_notarial)
--  ---------------------------------------------------------------------------
--  CONTEXTO DE NEGOCIO, que no se deduce del código:
--
--  En un Hak Sewa comparecen DOS apoderados, uno por parte:
--    · el del ARRENDADOR — representa al dueño de la tierra   → campos hsn_apoderado_*
--    · el del ARRENDATARIO — compra en nombre del comprador   → campos adq_apoderado_*
--
--  El Poder Notarial que emite Lawang es SIEMPRE el del comprador: el cliente,
--  desde España, apodera a alguien en Indonesia para comprar por él ante notario.
--  Que los dos nombres sean distintos es lo normal, son los dos lados de la mesa.
--
--  Decisión del cliente (17-ago-2026): UN solo poder vale para todos sus
--  contratos, no hace falta uno por escritura.
--
--  POR QUÉ UNA COLUMNA Y NO `contrato_padre_id`:
--    · la dirección correcta es MUCHOS contratos → UN poder, y `padre` solo
--      admite uno por fila;
--    · `contrato_padre_id` ya sirve para otra jerarquía (Carta de Reserva →
--      Bloqueo de Parcela) y la leen tres sitios que asumen un solo nivel.
--
--  PARA QUÉ SIRVE DE VERDAD: el nombre del apoderado del comprador, su NIK y la
--  fecha del poder se TECLEABAN a mano en cada Hak Sewa, copiando datos que
--  viven en el poder. Copiados a mano, derivan. Con el enlace se leen del origen
--  y los tres campos quedan de solo lectura.
--
--  GUARDAS (probadas con un bloque revertido, sin dejar rastro):
--    1. mismo comprador          → pasa
--    2. apuntar a un no-poder    → bloquea, nombrando el documento y su tipo
--    3. poder de otro comprador  → bloquea (compara pasaporte/email, nunca el
--       nombre: una tilde de más daría un bloqueo falso — criterio de LAW-51)
--    4. apuntarse a sí mismo     → bloquea
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.contratos
  add column if not exists poder_id uuid references public.contratos(id) on delete set null;

comment on column public.contratos.poder_id is
  'Poder Notarial (tipo=poa) bajo el que actua el apoderado DEL COMPRADOR en este contrato. Un poder cubre varios contratos.';

create index if not exists contratos_poder_id_idx on public.contratos(poder_id);

-- La función y el trigger completos están en la migración aplicada; se repiten
-- aquí para poder recrearlos desde el repo:
--   public.valida_poder_id()  +  trigger contratos_valida_poder_id
--   (before insert or update of poder_id, datos on public.contratos)
