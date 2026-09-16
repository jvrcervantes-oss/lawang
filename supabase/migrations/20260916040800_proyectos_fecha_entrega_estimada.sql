-- Fecha de entrega ESTIMADA del PROYECTO (agregada, para marketing/deck),
-- distinta de unidades.obra_fecha_entrega (fecha real de obra POR PARCELA).
-- No se derivan la una de la otra -- son dos hechos distintos con dueños
-- distintos (el promotor estima el proyecto; obra confirma parcela a parcela).
ALTER TABLE public.proyectos
  ADD COLUMN fecha_entrega_estimada_proyecto date,
  ADD COLUMN fecha_entrega_estimada_fijada_en date;

COMMENT ON COLUMN public.proyectos.fecha_entrega_estimada_proyecto IS
  'Estimacion agregada del PROYECTO (para el deck/marketing), NO la fecha real de obra por parcela -- esa es unidades.obra_fecha_entrega. No hay derivacion entre las dos.';
COMMENT ON COLUMN public.proyectos.fecha_entrega_estimada_fijada_en IS
  'Cuando se fijo la estimacion de arriba -- sin esto, la fecha envejece en silencio (regla del estudio: todo dato volatil lleva su fecha).';
