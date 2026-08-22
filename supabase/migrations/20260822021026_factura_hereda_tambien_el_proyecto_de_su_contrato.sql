-- LA FACTURA HEREDA TAMBIEN EL PROYECTO DE SU CONTRATO — auditoría 21-ago-2026.
--
-- Fallo mío del 19-ago, del mismo día que monté «el proyecto se referencia por
-- ENLACE». El enlace se resuelve por NOMBRE, y la pantalla de facturas guarda en
-- `proyecto_nombre` el proyecto MÁS la unidad:
--
--     "Tamarind Rise W3, 3.1 y 3.2 — B7"
--
-- Ese texto no es el nombre de ningún proyecto y nunca lo será, así que el
-- espejo no puede engancharlo. Resultado: cada factura con parcela nace huérfana
-- y no se entera de un renombrado. Los huérfanos pasaron de 12 a 44 y ninguno
-- dio un error.
--
-- La cura no es parsear el texto buscando el «—», que es adivinar: la factura YA
-- sabe de qué contrato es, y el contrato ya está enlazado a su proyecto. Se
-- hereda, igual que el cliente. Es la misma idea de siempre — el dato tiene un
-- dueño, y aquí el dueño es el contrato.
--
-- Las facturas SIN contrato (las 12 de LAW-38) siguen sin proyecto, y es
-- correcto: no tienen de dónde heredarlo.

create or replace function public.factura_hereda_cliente()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.contrato_id is not null then
    -- el CLIENTE (19-ago): la tabla de enlaces manda, el jsonb es el respaldo
    if new.client_id is null then
      select cc.client_id into new.client_id
        from public.contrato_compradores cc
       where cc.contrato_id = new.contrato_id and cc.rol = 'adquiriente_1'
       limit 1;

      if new.client_id is null then
        select nullif(c.datos->>'adq1_client_id','')::uuid into new.client_id
          from public.contratos c where c.id = new.contrato_id;
      end if;
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

-- El disparador tiene que mirar también `proyecto_id`, o un update que solo
-- toque esa columna no pasaría por aquí.
drop trigger if exists trg_factura_hereda_cliente on public.facturas;
create trigger trg_factura_hereda_cliente
  before insert or update of contrato_id, client_id, proyecto_id on public.facturas
  for each row execute function public.factura_hereda_cliente();;
