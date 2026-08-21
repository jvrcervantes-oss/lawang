-- Fuera los dos helpers de verificación: existían solo para poder probar la
-- RLS asumiendo el rol real. Dejarlos sería dejar en producción dos funciones
-- que hacen SET ROLE, que es justo lo que no debe quedarse suelto.
drop function if exists public._prueba_rls(text, text);
drop function if exists public._prueba_update(text, text, uuid);;
