-- ════════════════════════════════════════════════════════════════════════════
-- CARTA DE RESERVA CONDICIONADA VÍA PT PMA — tipo propio, serie CP · 7-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Motivo: el comprador de Mejan B2/B3/B4/B6/B7 (una S.L. española) condiciona la
-- transferencia de la Cuota de Reserva a que (a) la reserva quede sujeta a una due
-- diligence con devolución si falla, (b) desaparezca la referencia a Hak Sewa
-- porque la estructura de compra va a ser una PT PMA, y (c) pueda designar a esa
-- PT PMA como adquirente definitivo y transmitir después cada parcela por separado.
--
-- Ninguna de las tres cartas que ya existen sirve tal cual:
--   · CR (carta_reserva)              — 52 emitidas, sin condiciones ni devolución.
--   · CA (carta_reserva_ampliada)     — arrendamiento con obra: plazo de Hak Sewa,
--                                       escrow, garantías de construcción.
--   · CH (carta_reserva_hak_sewa)     — tiene las condiciones y la devolución, pero
--                                       su eje es Hak Sewa y su comprador es persona
--                                       física con pasaporte.
-- Se añade una CUARTA, ensamblada de las piezas ya validadas de las anteriores.
--
-- TIPO PROPIO, no compartido: TIPO_SLUG (app.html) mapea tipo→plantilla 1:1, así que
-- compartir tipo con cualquiera de las otras haría que reabrir un contrato guardado
-- cargase la plantilla equivocada. Mismo motivo por el que nacieron CA, CH y C2.
-- SERIE PROPIA (CP, no CR): por el número tiene que saberse con qué texto se firmó
-- una operación. CP se elige por simetría con CH — la carta "de Hak Sewa" y la carta
-- "de PMA" son las dos condicionadas y se distinguen por su vía de tenencia.
--
-- ⚠️ LA FUNCIÓN SE REESCRIBE DESDE SU DEFINICIÓN VIVA, NO DESDE ESTE DIRECTORIO.
-- `sql/carta_reserva_ampliada.sql` (31-jul) trae la versión de 8 ramas; la que corre
-- hoy en producción tiene 14 (se le añadieron PB, C2, HS, CH, PA y cc00014_timon).
-- Aplicar aquel fichero habría borrado seis series sin decir nada y el siguiente
-- contrato de esos tipos habría reventado con «Tipo de contrato sin numeracion
-- definida». Antes de tocar esta función: `pg_get_functiondef` y añadir la rama.
-- ════════════════════════════════════════════════════════════════════════════

create sequence if not exists public.contratos_cp_seq;

-- destructivo-ok: es un SWAP de CHECK, no un borrado de datos. Postgres no sabe
-- ampliar la lista de un CHECK en sitio: hay que soltarlo y volver a ponerlo, y
-- ambas van en la MISMA transaccion de apply_migration. Ni una fila se toca, y
-- el estado previo queda en `carta_reserva_pma_rollback.sql`. Es el mismo patron
-- con el que se anadieron las series CA (31-jul), CH y PA.
alter table public.contratos drop constraint if exists contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check
  check (tipo = any (array[
    'reserva_parcela','construccion','contrato_general','commercial_offer',
    'carta_reserva','carta_reserva_ampliada','acuerdo_comercial','protocolo_operativo',
    'ppjb_bonian','ppjb_bonian_c2','hak_sewa_notario','carta_reserva_hak_sewa',
    'poa','cc00014_timon',
    'carta_reserva_pma'
  ]));

create or replace function public.set_contrato_numero()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  n bigint;
  prefix text;
  seqname text;
begin
  if new.numero is not null then
    return new;
  end if;
  case new.tipo
    when 'reserva_parcela'    then prefix := 'RP'; seqname := 'public.contratos_rp_seq';
    when 'construccion'       then prefix := 'CC'; seqname := 'public.contratos_cc_seq';
    when 'contrato_general'   then prefix := 'CG'; seqname := 'public.contratos_cg_seq';
    when 'commercial_offer'   then prefix := 'CO'; seqname := 'public.contratos_co_seq';
    when 'carta_reserva'      then prefix := 'CR'; seqname := 'public.contratos_cr_seq';
    when 'carta_reserva_ampliada' then prefix := 'CA'; seqname := 'public.contratos_ca_seq';
    when 'acuerdo_comercial'  then prefix := 'AC'; seqname := 'public.contratos_ac_seq';
    when 'protocolo_operativo' then prefix := 'PO'; seqname := 'public.contratos_po_seq';
    when 'ppjb_bonian'        then prefix := 'PB'; seqname := 'public.contratos_pb_seq';
    when 'ppjb_bonian_c2'     then prefix := 'C2'; seqname := 'public.contratos_c2_seq';
    when 'hak_sewa_notario'   then prefix := 'HS'; seqname := 'public.contratos_hs_seq';
    when 'carta_reserva_hak_sewa' then prefix := 'CH'; seqname := 'public.contratos_ch_seq';
    when 'poa'                then prefix := 'PA'; seqname := 'public.contratos_poa_seq';
    when 'cc00014_timon'      then prefix := 'CC'; seqname := 'public.contratos_cc_seq';
    when 'carta_reserva_pma'  then prefix := 'CP'; seqname := 'public.contratos_cp_seq';
    else raise exception 'Tipo de contrato sin numeracion definida: %', new.tipo;
  end case;
  n := nextval(seqname);
  new.numero := prefix || lpad(n::text, 5, '0');
  return new;
end;
$function$;

-- Permisos: `contratos_tipo_permitido` solo filtra a los usuarios con rol 'agente'
-- (admin y super_admin pasan por definición). Los 10 agentes tienen su lista y
-- NINGUNO lleva 'carta_reserva_pma' — a propósito: un tipo nuevo no se abre a toda
-- la plantilla por el hecho de existir. Quien lo necesite se lo asigna un
-- administrador desde Usuarios, que es donde vive esa decisión.
