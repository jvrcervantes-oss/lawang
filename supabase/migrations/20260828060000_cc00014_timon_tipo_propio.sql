-- destructivo-ok: DROP + re-CREATE de un CHECK constraint (definicion, no
-- datos) para anadir 'cc00014_timon' a la lista de tipos permitidos, y un
-- UPDATE de UNA fila conocida por numero (CC00014), con rastro ANTES en
-- correcciones_datos -- no es un update masivo ni sin WHERE.
--
-- Ver contracts/sql/cc00014_timon_tipo_propio.sql para el porque completo.
-- Peticion del owner (28-ago-2026): "Necesito ese contrato configurarlo como
-- una nueva plantilla, sin inyectar datos, debe ir asi".

alter table public.contratos drop constraint contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check
  check (tipo = any (array[
    'reserva_parcela','construccion','contrato_general','commercial_offer',
    'carta_reserva','carta_reserva_ampliada','acuerdo_comercial',
    'protocolo_operativo','ppjb_bonian','ppjb_bonian_c2','hak_sewa_notario',
    'carta_reserva_hak_sewa','poa','cc00014_timon'
  ]::text[]));

insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
select 'contratos', id, 'tipo', 'construccion', 'cc00014_timon',
  'CC00014 (Timon Taeke van den Bosch) tiene clausulas propias negociadas a mano, distintas de la plantilla generica de Construccion -- se le da un tipo propio para que reabra siempre su propia plantilla fija (contracts/templates/cc00014_timon.html), nunca la generica. Peticion del owner 28-ago-2026.',
  'owner-28ago-via-CEO'
from public.contratos where numero = 'CC00014';

update public.contratos set tipo = 'cc00014_timon' where numero = 'CC00014';
