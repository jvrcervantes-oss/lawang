-- Parcelario: las dos lecturas del panel pasan a SECURITY INVOKER (9-oct-2026, revisor de código sobre 20261009041027).
-- erp-ok: lectura interna para una herramienta del estudio (AI Tools del panel), sin pantalla en el maestro
-- destructivo-ok: solo cambia el modo de seguridad de dos funciones de lectura; no toca ninguna fila
--
-- Por qué: su único llamador es service_role, que ya se salta la RLS, así que DEFINER no aportaba nada y dejaba el
-- GRANT como única barrera (patrones_tecnicos.md: las lecturas, INVOKER; una DEFINER comprueba permiso y
-- visibilidad dentro, y estas no comprobaban nada). Con INVOKER, si algún día se colara un EXECUTE para
-- authenticated, la RLS de unidades y proyectos seguiría frenándolo. Comprobado antes: service_role tiene SELECT en
-- las dos tablas y bypassrls. Prueba: contracts/sql/prueba_parcelario_lectura.sql.
alter function public.parcelario_proyectos() security invoker;
alter function public.parcelario_unidades(uuid) security invoker;
