-- Siembra del estado EXACTO de hoy (14-sep-2026), leído de
-- `assets/entidades_pago.js` → bankOptionsFor() y de `app.html` → CUENTA_DEFAULT.
-- Nada cambia de comportamiento con esta migración: lo que decidía el JS lo
-- decide ahora la tabla, diciendo lo mismo. El owner cambia lo que quiera desde
-- el panel, que es justo lo que no podía hacer.
--
-- Las 8 plantillas son las que traen <!--datos-bancarios--> (o la variante sin
-- título de cc00014_timon) y por tanto pintan selector de cuenta. El resto de
-- documentos, o no cobran, o llevan su cuenta FIJA en el marcador
-- <!--cuenta:CLAVE--> de la plantilla (ppjb_bonian_c2, anexo_y_bonian_c2) —
-- esos dos van a propósito con dos cuentas en el mismo documento y NO se tocan
-- desde aquí.
insert into public.plantillas_pago (slug, nombre, orden) values
  ('carta_reserva',           'Carta de Reserva',                     10),
  ('carta_reserva_ampliada',  'Carta de Reserva ampliada',            20),
  ('carta_reserva_hak_sewa',  'Carta de Reserva (Hak Sewa)',          30),
  ('carta_reserva_pma',       'Carta de Reserva Condicionada (PT PMA)',40),
  ('ppjb_parcela',            'Bloqueo de Parcela',                   50),
  ('ppjb_reserva',            'Contrato de Reserva de Proyecto',      60),
  ('ppjb_construccion',       'Contrato Maestro de Construcción',     70),
  ('cc00014_timon',           'Construcción · CC00014 Timon',         80)
on conflict (slug) do nothing;

-- 1) Carta de Reserva: UNA sola cuenta y precargada (owner, 8-sep-2026:
--    «precarga siempre Tepi Sun Gai (OCBC) y quita las demás»).
insert into public.plantilla_cuentas (slug, clave, es_default)
values ('carta_reserva', 'contractor_tepisungai', true)
on conflict (slug, clave) do nothing;

-- 2) Construcción: las CUATRO vías que tenía BANCOS_CONSTRUCCION.
insert into public.plantilla_cuentas (slug, clave)
select 'ppjb_construccion', c
from unnest(array['sandalwoods_dbs_sg','sandalwoods_danamon_eur',
                  'notario_sandy_sumba','contractor_sumba_eur']) as c
on conflict (slug, clave) do nothing;

-- 3) cc00014_timon: esas cuatro + la de PT Tepi Sun Gai (OCBC), que el owner
--    pidió SOLO para este contrato (BANCOS_CC00014_TIMON).
insert into public.plantilla_cuentas (slug, clave)
select 'cc00014_timon', c
from unnest(array['sandalwoods_dbs_sg','sandalwoods_danamon_eur',
                  'notario_sandy_sumba','contractor_sumba_eur',
                  'contractor_tepisungai']) as c
on conflict (slug, clave) do nothing;

-- 4) Reserva de Parcela: TODAS, escrows incluidos — es el único contrato que
--    pacta depósito en garantía notarial, así que ahí las de notario tienen
--    sentido (bankOptionsFor: `if(slug==='ppjb_parcela') return opts;`).
insert into public.plantilla_cuentas (slug, clave)
select 'ppjb_parcela', clave from public.cuentas_bancarias where activa
on conflict (slug, clave) do nothing;

-- 5) Las cuatro restantes: todas MENOS las de escrow, que era el
--    `return opts.filter(o => !o[0].startsWith('notario_'))` del final.
insert into public.plantilla_cuentas (slug, clave)
select p.slug, c.clave
from unnest(array['carta_reserva_ampliada','carta_reserva_hak_sewa',
                  'carta_reserva_pma','ppjb_reserva']) as p(slug)
cross join public.cuentas_bancarias c
where c.activa and not c.es_escrow
on conflict (slug, clave) do nothing;;
