-- Helper TEMPORAL de verificación: asume de verdad el rol `authenticated`
-- (SET LOCAL ROLE dentro de la función) para que la RLS se aplique. La conexión
-- del MCP es propietaria de las tablas y por tanto las bypasea: sin esto, un
-- "veo todas las filas" no distingue entre política correcta y política ausente.
-- Se borra al terminar la comprobación.
create or replace function public._prueba_rls(p_uid text, p_email text)
returns json language plpgsql security invoker as $$
declare r json;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'email', p_email, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select json_build_object(
    'contratos_que_ve', (select count(*) from public.contratos),
    'facturas_que_ve',  (select count(*) from public.facturas),
    'fichas_que_ve',    (select count(*) from public.usuarios),
    'es_agente',        public.es_agente(),
    'es_admin',         public.es_admin()
  ) into r;
  return r;
end $$;;
