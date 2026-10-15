-- LA FACTURA HEREDA EL CLIENTE SOLO DE contrato_compradores — 15-oct-2026 (sesión lawang-cola-2, resto de «Invitar al portal»).
--
-- `factura_hereda_cliente` (20260822021026) busca el cliente en contrato_compradores (rol 'adquiriente_1', la tabla con FK) y,
-- si no lo encuentra, cae a `contratos.datos->>'adq1_client_id'`: una copia en jsonb, sin FK, que puede apuntar a una ficha
-- borrada o a la de otro. Es el mismo respaldo que se le quitó hoy a _reclamo_pago_candidatos (20261015071004). Aquí se quita:
-- el dueño del dato es contrato_compradores, y si un contrato no tiene adquiriente_1 la factura nace sin cliente (como una sin
-- contrato), en vez de heredar lo que diga un texto.
--
-- ¿Cambia el cliente de alguna factura? El trigger solo rellena client_id cuando llega NULL (alta, o un update que lo pone a
-- null: 2159 lo hace al mover un recibí de contrato). El resultado nuevo solo difiere del viejo en un contrato con
-- adq1_client_id relleno y SIN fila adquiriente_1. La guarda de abajo mide eso y, si hay alguno, PARA: con 0, ningún contrato que
-- exista al aplicar da otro cliente a sus facturas. Ninguna fila existente se reescribe. Un contrato que se desajuste DESPUÉS (copia
-- en el jsonb sin fila adquiriente_1) dará facturas sin cliente: es lo buscado (sin dueño del dato no se hereda una copia).
-- Medir antes, en la viva (solo lectura): la misma select de la guarda.
--
-- Prueba: supabase/pruebas/factura_hereda_cliente_sin_copia.sql (rama). Reversión: volver a 20260822021026 (create or replace).

do $antes$
declare n int;
begin
  -- el mismo parser que contrato_guarda y sincronizar_compradores: la columna generada adq1_client_id (20260924071714)
  select count(*) into n
    from public.contratos c
   where c.adq1_client_id is not null
     and not exists (select 1 from public.contrato_compradores cc where cc.contrato_id = c.id and cc.rol = 'adquiriente_1');
  if n > 0 then
    raise exception 'PARADA: % contrato(s) con adq1_client_id y sin adquiriente_1 en contrato_compradores: sus facturas futuras cambiarían de cliente. Sincronizarlos antes (sincronizar_compradores) y repetir', n;
  end if;
end $antes$;

create or replace function public.factura_hereda_cliente()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.contrato_id is not null then
    -- el CLIENTE: solo de la tabla de enlaces (15-oct: sin el respaldo de la copia en el jsonb del contrato, que no tiene FK)
    if new.client_id is null then
      select cc.client_id into new.client_id
        from public.contrato_compradores cc
       where cc.contrato_id = new.contrato_id and cc.rol = 'adquiriente_1';
    end if;

    -- el PROYECTO (21-ago): del contrato, NO del propio texto de la factura
    if new.proyecto_id is null then
      select c.proyecto_id into new.proyecto_id
        from public.contratos c where c.id = new.contrato_id;
    end if;
  end if;
  return new;
end
$$;
revoke all on function public.factura_hereda_cliente() from public, anon, authenticated;
