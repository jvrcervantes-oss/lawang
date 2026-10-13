-- LAW-557 (13-oct-2026): ENCIENDE en la base de Lawang el alta de cliente CON documento.
-- NO es una migración: se lanza a mano (MCP supabase-lawang, execute_sql) SOLO DESPUÉS de que esté publicado el front
-- nuevo (editores.js con el alta por la edge, leads.js con el enlace a Clientes). EL ORDEN vive en un solo sitio: el
-- guion encargos/20261013_lawang_law557_558_guion.md de la agencia (migración y ficheros-kyc ANTES del front; este
-- fichero DESPUÉS del front; la retención, con su pasada en seco revisada antes del cron).
-- El front NO puede salir antes que la migración y la edge: instancia.js ya trae alta_exige_documento en Lawang y la
-- pantalla nueva solo da altas por la edge (revisor, 13-oct). Y este fichero no puede ir antes que el front: la
-- pantalla vieja llamaría a cliente_guarda(null, …) y el alta se quedaría sin salida.
-- Requisito: aplicada 20261013230000_law557_558_alta_con_documento_y_retencion_kyc y desplegada ficheros-kyc con
-- las acciones alta_*.
--
-- Con esto encendido:
--   · cliente_guarda(null, …) se niega: «El alta de un cliente va con su documento de identidad: recarga la página y usa
--     Nuevo cliente» (22023). Editar una ficha no cambia.
--   · crm_lead_ficha_crear se niega a CREAR (devolver la ficha existente por email sigue igual).
--
-- VUELTA ATRÁS (apagar, sin borrar nada):
--   update public.config_instancia set valor = 'false'::jsonb where clave = 'alta_exige_documento';

insert into public.config_instancia (clave, valor, descripcion)
values ('alta_exige_documento', 'true'::jsonb,
        'LAW-557: el alta de un cliente va con su documento de identidad en una sola operación (edge ficheros-kyc, acción alta). Con true, cliente_guarda(null) y el «Crear ficha» del CRM de leads se niegan.')
on conflict (clave) do update set valor = excluded.valor, descripcion = excluded.descripcion, actualizado_en = now();

-- Comprobación (debe salir true):
select (valor = 'true'::jsonb) as encendido from public.config_instancia where clave = 'alta_exige_documento';
