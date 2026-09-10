-- destructivo-ok: DROP + re-CREATE de un CHECK constraint (definicion, no
-- datos) para anadir 'cc00014_timon' a la lista de tipos permitidos -- mismo
-- patron que cuando se dieron de alta ppjb_bonian_c2/hak_sewa_notario/etc.
-- No borra ni toca ninguna fila.
alter table public.contratos drop constraint contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check
  check (tipo = any (array[
    'reserva_parcela','construccion','contrato_general','commercial_offer',
    'carta_reserva','carta_reserva_ampliada','acuerdo_comercial',
    'protocolo_operativo','ppjb_bonian','ppjb_bonian_c2','hak_sewa_notario',
    'carta_reserva_hak_sewa','poa','cc00014_timon'
  ]::text[]));;
