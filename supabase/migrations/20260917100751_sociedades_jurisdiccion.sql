-- La jurisdiccion deja de deducirse de la clave literal.
--
-- Hallazgo MEDIA de Legal en la consulta de deploy del 17-sep-2026:
-- `contracts/app.html` avisaba de que las nueve plantillas declaran al Promotor
-- «sociedad de nacionalidad Indonesia» comparando la clave contra el literal
-- 'sandal_woods_ltd'. Mientras las sociedades nacian por SQL eso aguantaba;
-- desde que se dan de alta desde un panel, la cuarta empresa imprimiria esa
-- declaracion falsa sin que nada avisara. Es el mismo patron que `es_escrow` en
-- cuentas_bancarias: lo dice la FILA, no su nombre.
alter table public.sociedades
  add column if not exists es_indonesia boolean not null default true;

comment on column public.sociedades.es_indonesia is
  'Las 9 plantillas de contrato declaran al Promotor como sociedad indonesia. En false, la pantalla avisa de que esa clausula hay que corregirla a mano.';

update public.sociedades set es_indonesia = false where clave = 'sandal_woods_ltd';

grant update (es_indonesia) on public.sociedades to authenticated;;
