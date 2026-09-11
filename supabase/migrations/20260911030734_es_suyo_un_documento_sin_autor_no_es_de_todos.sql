-- es_suyo(): un documento SIN AUTOR no es "de todos" — 11-sep-2026
--
-- QUÉ PASABA. La función decía `autor is null or autor = auth.email() or es_admin()`.
-- Ese `autor is null` convertía cualquier documento con `creado_por` nulo en
-- propiedad de CUALQUIER agente activo. Medido el 11-sep: 10 contratos y 8 facturas
-- sin autor, visibles —y EDITABLES— por los 20 miembros del equipo, incluidos 3
-- contratos de Sumba Hills y 1 de Mejan Village que veía una agente asignada solo a
-- Bonian Village. Ese fue el síntoma que reportó el owner.
--
-- POR QUÉ SE ARREGLA AQUÍ Y NO EN CADA POLICY. Es la SEGUNDA vez que muerde: en
-- agosto la campana de avisos enseñó avisos de solo-admins al equipo entero por lo
-- mismo, y la policy de DELETE de `contratos` ya llevaba un `creado_por IS NOT NULL`
-- pegado a mano para taparlo en un solo sitio. Parchear el call site deja la mina
-- puesta para el siguiente. Las policies de `contratos`, `facturas`, `contrato_firmas`
-- y `recibi_aplicaciones`, y la función `guardar_recibi`, heredan el arreglo sin
-- tocarlas: por eso vive en la función.
--
-- POR QUÉ `es_admin()` VA PRIMERO Y NO DENTRO DE UN `autor is not null and (...)`.
-- La policy SELECT de `contrato_firmas` es la única que llama a `es_suyo` SIN un
-- `or es_manager_de(...)` al lado. Si el nulo dejara de contar también para los
-- admins, se quedarían ciegos sobre las firmas de esos 18 documentos huérfanos.
-- Con esta forma, un documento sin autor queda visible solo para admin y
-- super_admin, que son quienes pueden reasignarlo (botón "Reasignar autor",
-- assets/autoria.js), y desaparece para el resto del equipo.
--
-- LOS 18 HUÉRFANOS NO SE RELLENAN AQUÍ. No se inventa un autor: se reasignan uno a
-- uno desde el botón, que deja rastro en `correcciones_datos`.
--
-- VERIFICADO por impersonación antes/después (agente Andrea: 10 -> 0 contratos;
-- agente Ismael: 2 propios intactos; sales_manager Victor: 15, sus 6 + los 9 del
-- proyecto que supervisa; admin Fran: 223, huérfanos incluidos).

create or replace function public.es_suyo(autor text)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select public.es_admin() or coalesce(autor = (select auth.email()), false)
$function$;
