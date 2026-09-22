-- bot_consultas.respuesta_comprador — el recorte para el comprador, guardado.
-- 22-sep-2026, encargo 20260922_lawang_asistente_faq_temas (revisión de código
-- de S3). Construye, no destruye: una columna nueva, nada más.
--
-- POR QUÉ. La edge devuelve `borrador_comprador` (solo los puntos no retirados,
-- sin frases fijas ni marca) pero no lo guardaba: al reabrir una consulta
-- desde el historial, «Ver» solo tenía `respuesta` (el borrador ENTERO, con
-- «no lo confirmes al comprador…» dentro) y lo cargaba en el área editable que
-- «Copiar» manda al portapapeles. La decisión de Legal (rev. #43) es que ese
-- texto nunca entre en el portapapeles, así que el recorte se guarda junto al
-- borrador y el historial lo lee. Lo escribe la edge en el mismo insert; el
-- agente no escribe aquí (bot_consultas sigue sin policy de UPDATE).
alter table public.bot_consultas
  add column if not exists respuesta_comprador text;
comment on column public.bot_consultas.respuesta_comprador is
  'Recorte para el comprador del borrador (borradorComprador en la edge): solo puntos no retirados, sin frases fijas, sin marca IA. NULL si la consulta se descarto. Es lo que el historial carga en el area editable.';
