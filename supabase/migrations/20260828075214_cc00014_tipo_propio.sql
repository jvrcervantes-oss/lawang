-- destructivo-ok: UPDATE de UNA fila conocida por id (CC00014), con rastro
-- ANTES en correcciones_datos -- no es un update masivo ni sin WHERE.
--
-- CC00014 pasa de tipo='construccion' (la plantilla generica) a su tipo
-- PROPIO 'cc00014_timon' (mismo motivo que ppjb_bonian_c2, comentado en
-- contracts/app.html: compartir tipo con la plantilla generica pisaria la
-- entrada del mapa inverso TIPO_SLUG y reabrir este contrato cargaria la
-- plantilla equivocada). No afecta a la facturacion: unidad_parte_cobrada y
-- avanza_unidad_por_cobro trabajan por contrato_padre_id/unidad_id, nunca
-- filtran por tipo. Peticion del owner (28-ago-2026): "configurarlo como una
-- nueva plantilla, sin inyectar datos, debe ir asi".

insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
select 'contratos', id, 'tipo', 'construccion', 'cc00014_timon',
  'CC00014 (Timon Taeke van den Bosch) tiene clausulas propias negociadas a mano, distintas de la plantilla generica de Construccion -- se le da un tipo propio para que reabra siempre su propia plantilla fija (contracts/templates/cc00014_timon.html), nunca la generica. Peticion del owner 28-ago-2026.',
  'owner-28ago-via-CEO'
from public.contratos where numero = 'CC00014';

update public.contratos set tipo = 'cc00014_timon' where numero = 'CC00014';;
