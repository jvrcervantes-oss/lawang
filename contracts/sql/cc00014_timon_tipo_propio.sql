-- Ya aplicado en producción (28-ago-2026, petición del owner: "Necesito ese
-- contrato configurarlo como una nueva plantilla, sin inyectar datos, debe
-- ir así"). Copia de repo-de-registro, no se vuelve a ejecutar.
--
-- CC00014 (construcción, Timon Taeke van den Bosch, Tamarind Rise · modelo
-- Dali) llegó con un .docx ya negociado a mano: 78 tramos de texto resaltados
-- en amarillo frente a la plantilla genérica de Construcción, cláusulas
-- propias (fase de construcción ya iniciada en marzo 2026 antes de firmar,
-- vínculo con un Land Lease Agreement notarial propio, arbitraje SIAC en vez
-- de BANI, calendario de pagos propio...). Igual que ppjb_bonian_c2 (serie
-- C2, "un solo ejemplar, texto fijo"), se convierte en su propia plantilla
-- estática (contracts/templates/cc00014_timon.html) en vez de forzarlo por
-- el sistema genérico de campos, que perdería exactamente las cláusulas que
-- lo hacen distinto.
--
-- Primero se amplía el CHECK de contratos.tipo para admitir el tipo propio
-- (mismo patrón que al dar de alta ppjb_bonian_c2/hak_sewa_notario en su
-- momento), y luego se pasa CC00014 de 'construccion' a 'cc00014_timon' —
-- necesario porque TIPO_SLUG (contracts/app.html) es un mapa inverso
-- tipo→plantilla: compartir tipo con la genérica pisaría la entrada y
-- reabrir este contrato cargaría la plantilla equivocada. No afecta a la
-- facturación: unidad_parte_cobrada y avanza_unidad_por_cobro trabajan por
-- contrato_padre_id/unidad_id, nunca filtran por tipo.

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
