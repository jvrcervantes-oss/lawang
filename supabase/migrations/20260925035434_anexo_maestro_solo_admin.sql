-- El Anexo Maestro lo decide administración — 25-sep-2026.
--
-- Desde hoy el documento de tipo 'plano' de un modelo es el ÚNICO anexo del
-- contrato de Construcción (decisión del owner): ya no hay PDF de respaldo en el
-- repo ni subida a mano en ese contrato. Lo que diga esta fila es lo que firma el
-- comprador como Apéndice.
--
-- Hasta hoy `modelo_docs: escribir` era es_agente() para todo: cualquier agente
-- podía subir un PDF, marcarlo como plano, cambiarle el techo o borrarlo, y con
-- eso cambiar el anexo de todos los contratos que se generaran después
-- (Seguridad, revisión previa #86). `modelos_villa` ya exige es_admin() para
-- escribir; esto lo iguala SOLO para los planos. El resto de documentos (fichas,
-- renders, memorias) los sigue subiendo y retipando cualquier agente, como antes.
--
-- USING mira la fila como está (no se toca un plano ajeno); WITH CHECK, como
-- queda (no se convierte otra cosa en plano). El bucket no necesita cambio: no
-- hay policy UPDATE en `modelos`, así que un fichero subido no se sobrescribe, y
-- un fichero sin fila tipo 'plano' no llega a ningún contrato.

-- ALTER y no DROP+CREATE: la policy se estrecha sin haber un instante sin ella.
alter policy "modelo_docs: escribir" on public.modelo_documentos
  using     (public.es_agente() and (tipo is distinct from 'plano' or public.es_admin()))
  with check (public.es_agente() and (tipo is distinct from 'plano' or public.es_admin()));
