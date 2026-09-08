-- ============================================================================
-- ADENDA — tipo de contrato y serie propia (AD).  8-sep-2026, encargo del owner
-- ----------------------------------------------------------------------------
-- PARA QUE. Modificar un contrato YA FIRMADO sin rehacerlo. El contrato madre se
-- queda intacto y firmado; la adenda es una pagina que dice que se modifica y
-- ratifica el resto. Hasta hoy habia dos salidas y las dos malas:
--   · anular la firma y reeditar  -> el comprador vuelve a firmar el contrato
--     entero y se pierde la traza de QUE cambio;
--   · duplicarlo en uno nuevo     -> dos documentos vivos sobre la misma
--     operacion, sin vinculo entre ellos.
-- El owner lo pidio con CC00014 delante: «el cliente firmo y requiere una
-- modificacion, es un conazo estar asi».
--
-- TIPO PROPIO, no reutilizar uno existente: `TIPO_SLUG` en app.html es un mapa
-- inverso tipo->slug, asi que compartir tipo hace que reabrir un documento
-- guardado cargue la plantilla equivocada. Es el mismo motivo por el que ya
-- nacieron las series CA, CH, C2 y CP.
-- SERIE PROPIA (AD): por el numero tiene que saberse con que texto se firmo.
--
-- SIN PRECIO A PROPOSITO. La adenda no declara `precio_total`. Si lo hiciera,
-- Operaciones sumaria el importe otra vez sobre la misma operacion — el fallo
-- que ya dio 328.000 EUR por una villa de 164.000 (ver vocabulario.js).
--
-- ⚠️ LA FUNCION Y EL CHECK SE REESCRIBEN DESDE SU DEFINICION VIVA, leida con
-- `pg_get_functiondef` / `pg_get_constraintdef`, NUNCA desde este directorio:
-- estos ficheros van por detras de produccion con facilidad, y aplicar una copia
-- vieja borraria series enteras sin decir nada. Al anadir la rama 16 (adenda) la
-- funcion viva tenia 15.
--
-- APLICADO en produccion el 8-sep-2026 (migracion `adenda_tipo_y_serie_ad`) y
-- verificado con un insert dentro de una transaccion revertida: devolvio
-- AD00001. La secuencia se dejo en 1 con `setval(..., 1, false)` para que la
-- primera adenda real sea AD00001 y no AD00002.
-- ============================================================================

create sequence if not exists public.contratos_ad_seq;

-- destructivo-ok: es un SWAP de CHECK, no un borrado de datos. Postgres no sabe
-- ampliar la lista de un CHECK en sitio: hay que soltarlo y volver a ponerlo, y
-- las dos van en la MISMA transaccion. Ni una fila se toca.
alter table public.contratos drop constraint if exists contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check
  check (tipo = any (array[
    'reserva_parcela','construccion','contrato_general','commercial_offer',
    'carta_reserva','carta_reserva_ampliada','acuerdo_comercial','protocolo_operativo',
    'ppjb_bonian','ppjb_bonian_c2','hak_sewa_notario','carta_reserva_hak_sewa',
    'poa','cc00014_timon','carta_reserva_pma',
    'adenda'
  ]));

-- La rama nueva es la ultima; el resto es la definicion viva tal cual estaba.
-- (cuerpo completo en la migracion `adenda_tipo_y_serie_ad`; se repite aqui solo
--  la linea que se anade, para que este fichero no compita con la funcion viva)
--   when 'adenda'             then prefix := 'AD'; seqname := 'public.contratos_ad_seq';
