alter table public.clients
  add column if not exists idioma_comunicacion text not null default 'es'
  check (idioma_comunicacion in ('es','en','id'));

comment on column public.clients.idioma_comunicacion is
  'Idioma preferido para comunicarse con este comprador (es/en/id). Default es: la mayoría de la cartera actual.';
;
