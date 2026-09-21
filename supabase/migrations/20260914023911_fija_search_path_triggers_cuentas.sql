-- Los advisors de Supabase marcan `function_search_path_mutable` en las dos
-- funciones del 14-sep. Con el `search_path` heredado de la sesión, quien pueda
-- crear un esquema antes en la ruta puede colar su propia `now()` o su propia
-- tabla `plantilla_cuentas` y el trigger la usaría. En un trigger que decide en
-- qué cuenta cobra un contrato eso no es teórico: es el sitio exacto donde no
-- puede haber ambigüedad sobre a qué tabla se escribe.
-- `set search_path = ''` obliga a que todo vaya cualificado, y ya lo está.
alter function public.un_solo_default_por_plantilla() set search_path = '';
alter function public.sella_cuenta_bancaria() set search_path = '';;
