-- `contrato_cobrado` perdia dinero realmente cobrado -- 14-ago-2026.
--
-- SINTOMA (lo trajo el owner): CR00020, Jorge Miguel Domingo Berenguer / Mayka
-- Nunez Saez, parcela C5 de Bonian Village. El cliente paga la reserva, se le
-- emite factura y recibi (REC00019, 1.000 EUR, con justificante) y el contrato
-- sigue diciendo 0 cobrado.
--
-- CAUSA. La funcion sumaba por dos ramas que no cubren todos los casos:
--   (A) importes aplicados cuya FACTURA es de este contrato, y
--   (B) el total de los recibis de este contrato que NO tienen ninguna aplicacion.
-- REC00019 esta aplicado a INV00001, una factura que NO tiene `contrato_id`
-- (una de las 12 antiguas de LAW-38). Asi que:
--   · la rama A no lo ve, porque la factura no es de CR00020 (no es de nadie);
--   · la rama B lo descarta, porque el recibi SI tiene una aplicacion.
-- El dinero se cae por la rendija entre las dos.
--
-- Y lo importante, que es por lo que esto no es "un caso raro": la rama B se
-- desactiva con que exista UNA aplicacion cualquiera. O sea que el mismo agujero
-- se traga tambien:
--   · el resto no aplicado de un recibi aplicado en PARTE (recibi de 1.000
--     aplicado 400 a una factura del contrato -> los otros 600 desaparecian);
--   · cualquier recibi aplicado a una factura sin `contrato_id`, y de esas
--     quedan 3 vivas por 60.000 EUR: el problema se REPRODUCE cada vez que
--     alguien aplique un cobro nuevo contra una de ellas.
-- Hoy no habia ningun recibi parcial, pero nada lo impedia.
--
-- ARREGLO. La rama B deja de ser "recibis sin ninguna aplicacion" y pasa a ser
-- "la parte de cada recibi que no se ha atribuido a ningun contrato": su total
-- menos lo aplicado a facturas que SI tienen `contrato_id`. El dinero de un
-- recibi pertenece al contrato del recibi salvo que se haya atribuido
-- explicitamente a otro.
--
-- Se conserva a proposito el caso legitimo de aplicacion CRUZADA entre padre e
-- hijo (un recibi del Bloqueo aplicado a una factura de su Construccion): esa
-- aplicacion apunta a una factura CON contrato, asi que sigue contando en el
-- contrato de la factura y no se duplica en el del recibi.
--
-- Comprobado antes de aplicar, calculando la formula nueva contra los 36
-- contratos sin tocar la funcion: cambia EXACTAMENTE UNO, CR00020, de 0 a 1.000.
-- Todos los demas dan el mismo numero que hoy.
--
-- LO QUE ESTO **NO** ARREGLA, y sigue abierto:
--   · Los 9 recibis sin `contrato_id` (166.610 EUR de clientes reales) siguen
--     invisibles: no hay contrato al que sumarlos. Es LAW-38/LAW-40 y es una
--     decision del owner, no un bug de codigo: hay que decir a que contrato
--     corresponde cada uno.
--   · La parcela no avanza de estado si `unidades.contrato_id` esta suelto.
--     Ver LAW-55.

create or replace function public.contrato_cobrado(p_contrato_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select
    -- (A) lo aplicado a facturas DE ESTE contrato
    coalesce((
      select sum(ra.importe_aplicado)
        from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
        join public.facturas f on f.id = ra.factura_id
       where f.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not coalesce(f.anulada, false)
    ), 0)
    +
    -- (B) de los recibis de este contrato, la parte que no se ha atribuido a
    --     NINGUN contrato: ni aplicada a una factura con contrato, ni aplicada
    --     en absoluto. Antes esta rama se apagaba entera con una sola
    --     aplicacion, y ahi es donde se perdia el dinero.
    coalesce((
      select sum(
               r.total - coalesce((
                 select sum(ra.importe_aplicado)
                   from public.recibi_aplicaciones ra
                   join public.facturas f2 on f2.id = ra.factura_id
                  where ra.recibi_id = r.id
                    and f2.contrato_id is not null
                    and not coalesce(f2.anulada, false)
               ), 0)
             )
        from public.facturas r
       where r.tipo = 'recibi'
         and r.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
    ), 0)
$$;

-- Comprobacion despues de correrlo:
--   select numero, public.contrato_cobrado(id) from public.contratos
--    where numero in ('CR00020','RP00025','CC00010');
--   -- CR00020 debe dar 1000 (antes 0); los otros dos, 39220 y 41620 igual que antes.
