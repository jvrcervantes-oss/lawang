-- LA FACTURA HEREDA EL CLIENTE DE SU CONTRATO — 21-ago-2026.
--
-- Lo caza el chequeo de salud, dos dias despues de dejarlo en cero: 31 facturas
-- con contrato y SIN ficha de cliente. 30 son de hoy — 15 proformas y 15 recibis
-- de cinco contratos nuevos (RP00061..RP00065), y esos contratos SI tienen su
-- ficha enlazada. O sea que el dato existia y no se copiaba.
--
-- Por que paso. `facturas.client_id` se anadio el 19-ago y se rellena desde la
-- pantalla de Facturas. Pero hay TRES caminos que crean facturas:
--   1. la herramienta de Facturas          → se arreglo el 19-ago
--   2. la proforma automatica de Contratos → no lo hacia
--   3. `guardar_recibi()`                  → no lo hacia
-- Arreglar el que tenias delante y no preguntar cuantos hay es exactamente el
-- fallo. Y no dio ningun error: la factura se guarda igual, solo que sin poder
-- saber si sus datos siguen siendo los del comprador.
--
-- Por eso el arreglo va en la BASE y no en las tres pantallas: el cliente de una
-- factura NO es un dato que se teclea, es una consecuencia de su contrato. Lo
-- rellena quien es dueno del dato. Un cuarto camino que aparezca manana nace
-- arreglado.
--
-- No pisa lo que ya venga puesto: si la pantalla manda un client_id, manda ese.

create or replace function public.factura_hereda_cliente()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.client_id is null and new.contrato_id is not null then
    -- La tabla de enlaces manda; el jsonb del contrato es el respaldo. Mismo
    -- orden que en el resto de la suite: el ENLACE es la verdad y el texto su
    -- espejo (ver contexto/patrones_tecnicos.md).
    select cc.client_id into new.client_id
      from public.contrato_compradores cc
     where cc.contrato_id = new.contrato_id and cc.rol = 'adquiriente_1'
     limit 1;

    if new.client_id is null then
      select nullif(c.datos->>'adq1_client_id','')::uuid into new.client_id
        from public.contratos c where c.id = new.contrato_id;
    end if;
  end if;
  return new;
end
$$;

revoke execute on function public.factura_hereda_cliente() from public;

drop trigger if exists trg_factura_hereda_cliente on public.facturas;
create trigger trg_factura_hereda_cliente
  before insert or update of contrato_id, client_id on public.facturas
  for each row execute function public.factura_hereda_cliente();;
