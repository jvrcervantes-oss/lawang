-- Las funciones *_equipo() dejan de saltarse la RLS — 11-sep-2026
--
-- QUÉ PASABA. `contratos_equipo()` y sus cuatro hermanas eran SECURITY DEFINER con
-- un único filtro: `where es_agente()`. Es decir, CUALQUIER miembro activo del
-- equipo veía los 223 contratos y las 371 facturas del estudio en Operaciones,
-- Facturas, Compradores, Vencimientos y en la propia portada de /intranet/ —
-- mientras la pantalla de Contratos, que lee la tabla directa, sí respetaba la RLS.
-- Dos caminos al mismo dato y solo uno con candado.
--
-- Se escribieron así el 7-ago con un motivo honesto que está en el código de
-- operaciones-cuentas.js: «Operaciones existe justo para cruzar los de todo el
-- equipo». Era cierto entonces, cuando los 20 agentes tenían los 29 proyectos.
-- Hoy Andrea tiene uno, Ismael otro y Miguel otro, y el bypass seguía entero: por
-- eso una agente asignada solo a Bonian Village veía contratos de Sumba Hills.
--
-- DECISIÓN DEL OWNER, 11-sep-2026, con los números por persona delante: una sola
-- regla en toda la suite — cada uno ve lo que creó, más lo que supervisa si es
-- manager, y admin/super_admin lo ven todo. Es exactamente la policy que ya tenía
-- la tabla.
--
-- POR QUÉ `SECURITY INVOKER` Y NO REPETIR EL PREDICADO DENTRO. Copiar
-- `es_suyo(...) or es_manager_de(...)` aquí serían dos copias de la misma regla en
-- dos sitios, y ése es el fallo que esta suite ya ha pagado cinco veces (ver
-- contexto/suite_lawang.md: «una lista a mano en dos sitios ES el bug»). Con
-- INVOKER la función no decide nada: hereda la policy de la tabla, y el día que la
-- policy cambie, cambian con ella sin que nadie se acuerde de venir aquí.
--
-- `create or replace`, NUNCA drop+create: replace conserva el ACL actual — a estas
-- funciones ya se les revocó `anon` en su día (20260807043959) y un drop se lo
-- devolvería a PUBLIC.
--
-- VERIFICADO por impersonación de las 24 fichas activas con la herramienta:
-- admin/super_admin 223 contratos (sin cambio), Yesy 97, Santiago 70, Gus 38,
-- Carmen 36, Fernando 34, David Ortega 31, Victor 15, Maretti 6, Jose 3,
-- Noelia 2, Ismael 2, y 0 para quien aún no ha creado ninguno — Andrea incluida,
-- que es el caso reportado. Y la aritmética del dinero, invariante: la huella
-- md5 fila a fila de facturas_pendiente_equipo() y contratos_cobrado_equipo()
-- vista por un admin es IDÉNTICA antes y después (113 filas / 2.740.534,59 y
-- 223 filas / 1.735.048,41).

-- 1) Las firmas siguen a su contrato. La policy de `contrato_firmas` era la única
--    que llamaba a es_suyo() SIN el `or es_manager_de(...)` al lado. Sin esto, con
--    INVOKER un sales_manager vería en Operaciones los contratos del proyecto que
--    supervisa pero NO sus firmas: media pantalla.
alter policy "agentes leen firmas de sus contratos" on public.contrato_firmas
  using (
    public.es_agente() and exists (
      select 1 from public.contratos c
       where c.id = contrato_firmas.contrato_id
         and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))));

-- 2) Cuánto se ha cobrado de una factura NO es una cuestión de permisos, es
--    aritmética. El recibí que la salda pudo emitirlo otro agente: si la suma
--    pasara por la RLS del que mira, una factura cobrada al 100% volvería a salir
--    "vencida" en rojo en cuanto el cobro lo hubiera registrado un compañero.
--    Por eso el CÁLCULO sigue siendo DEFINER y completo, y lo único que filtra la
--    RLS son las FILAS. Mismo reparto que ya tenía contrato_cobrado().
create or replace function public.factura_aplicado(p_factura uuid)
returns numeric
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(sum(ra.importe_aplicado), 0)
    from public.recibi_aplicaciones ra
    join public.facturas r on r.id = ra.recibi_id
   where ra.factura_id = p_factura
     and not coalesce(r.anulada, false)
$function$;

-- Una función nueva nace con EXECUTE para PUBLIC: una DEFINER que devuelve dinero
-- a cambio de un uuid quedaría al alcance de `anon` por PostgREST. Mismo cierre que
-- hubo que hacer a mano en 20260807043959_contratos_equipo_revoke_anon.sql.
revoke execute on function public.factura_aplicado(uuid) from public, anon;
grant  execute on function public.factura_aplicado(uuid) to authenticated, service_role;

-- 3) Las cinco, a INVOKER. El `where es_agente()` se queda: ya no es el candado
--    (lo es la RLS), pero sigue cortando en seco a una sesión que no sea del equipo.
create or replace function public.contratos_equipo()
returns setof public.contratos
language sql
security invoker
set search_path to ''
as $function$ select * from public.contratos where public.es_agente(); $function$;

create or replace function public.facturas_equipo()
returns setof public.facturas
language sql
security invoker
set search_path to ''
as $function$ select * from public.facturas where public.es_agente(); $function$;

create or replace function public.contrato_firmas_equipo()
returns table(id uuid, contrato_id uuid, estado text, firmante_nombre text,
              firmante_email text, firmante_rol text, creado_en timestamptz,
              firmado_en timestamptz, expira_en timestamptz, snapshot_path text)
language sql
stable security invoker
set search_path to ''
as $function$
  select cf.id, cf.contrato_id, cf.estado,
         cf.firmante_nombre, cf.firmante_email, cf.firmante_rol,
         cf.creado_en, cf.firmado_en, cf.expira_en, cf.snapshot_path
    from public.contrato_firmas cf
   where public.es_agente();
$function$;

create or replace function public.contratos_cobrado_equipo()
returns table(contrato_id uuid, cobrado numeric)
language sql
stable security invoker
set search_path to ''
as $function$
  select c.id, public.contrato_cobrado(c.id)
    from public.contratos c
   where public.es_agente();
$function$;

create or replace function public.facturas_pendiente_equipo()
returns table(factura_id uuid, pendiente numeric)
language sql
stable security invoker
set search_path to ''
as $function$
  select f.id, f.total - public.factura_aplicado(f.id)
    from public.facturas f
   where f.tipo = 'factura'
     and not coalesce(f.anulada, false)
     and public.es_agente();
$function$;
