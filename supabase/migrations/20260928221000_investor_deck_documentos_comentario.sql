-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- El drop+create de 20260928220000 se llevó el comentario de la función (revisor de código, 28-sep). Se repone al día.
comment on function public.investor_deck_documentos(text) is
  'Documentos que un proyecto ofrece en el investor deck público. Lo que se sirve lo decide investor_deck_documento_visible (publicado, no confidencial, no faq, deck abierto; enlace http(s) o fichero subido de tipo admitido). Un fichero sale por la edge deck-documento. Devuelve titulo (español) y titulo_i18n {en,id}; nunca path ni creado_por.';
