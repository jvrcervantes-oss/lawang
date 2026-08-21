-- Agrupa campañas bajo un mismo agente humano para la vista compartida /a/<testigo>.
-- Texto libre que rellena el owner (sin lista fija en el codigo); vacio o NULL nunca
-- cuenta como grupo -- lo aplica el servidor, no solo el aviso del modal.
alter table public.axisworks_meta_campanas add column agente text;

comment on column public.axisworks_meta_campanas.agente is
  'Texto libre: campañas con el mismo agente (tras normalizar) comparten una sola vista de agente (/a/<testigo>). NULL/vacío = no agrupa.';;
