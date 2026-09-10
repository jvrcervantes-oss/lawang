-- Una vista en Postgres corre por defecto con los permisos de SU DUEÑO, asi que **ignora la
-- RLS de las tablas que lee**: `lead_sugerencia`, creada hace un momento, habria dejado a un
-- anonimo leer por PostgREST el cruce email-a-contrato de personas reales, pese a que `leads`
-- tiene RLS y solo permite INSERT al rol anon. Es el fallo que el estudio ya tiene fichado
-- (memoria `reference_supabase_security_definer_lectura_publica`), y `revoke ... from public`
-- por si solo no basta contra los roles de Supabase.
-- Con `security_invoker = on` la vista se ejecuta con los permisos de quien pregunta: el
-- panel entra con la service key y ve todo; un anonimo choca con la RLS de `leads` y no ve
-- nada. La proteccion pasa a ser la misma que ya protege la tabla, no una copia aparte.
alter view public.lead_sugerencia set (security_invoker = on);

-- Una sola vista para el tablero: el panel hace UNA llamada en vez de tres y unir a mano.
create or replace view public.lead_tablero
with (security_invoker = on) as
select l.id, l.created_at, l.source, l.name, l.email, l.whatsapp,
       l.respuestas, l.campaign_id, l.ad_id, l.form_id,
       coalesce(e.estado, 'nuevo')            as estado,
       e.responsable,
       coalesce(e.estado_desde, l.created_at) as estado_desde,
       s.etapa                                as sugerencia,
       s.contrato_numero                      as sugerencia_contrato,
       (select count(*) from public.lead_notas n where n.lead_id = l.id) as notas
from public.leads l
left join public.lead_estado e     on e.lead_id = l.id
left join public.lead_sugerencia s on s.lead_id = l.id;;
