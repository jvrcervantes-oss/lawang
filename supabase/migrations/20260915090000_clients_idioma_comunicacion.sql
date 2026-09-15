-- Idioma preferido de comunicación del comprador (encargo del owner, 15-sep-2026):
-- "necesitamos poder elegir el idioma de las comunicaciones del cliente". Mismo
-- juego ES/EN/ID que ya usa el resto de la suite (idioma.js, i18n.js, y los propios
-- documentos, que ya redactan en los tres) — no se inventa un cuarto valor.
-- Preferencia, no traducción automática: guardar el dato no reescribe en qué
-- idioma salen los correos ya existentes, eso es un cableado aparte si hace falta.
alter table public.clients
  add column if not exists idioma_comunicacion text not null default 'es'
  check (idioma_comunicacion in ('es','en','id'));

comment on column public.clients.idioma_comunicacion is
  'Idioma preferido para comunicarse con este comprador (es/en/id). Default es: la mayoría de la cartera actual.';
