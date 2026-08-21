-- destructivo-ok: el unico DELETE borra la fila de prueba «INTRUSO» que yo mismo
-- acabo de meter al comprobar el agujero. No toca ningun aviso real.
--
-- 🔴 AGUJERO ENCONTRADO al verificar sin sesion (4-ago-2026): `anotar_aviso`
-- respondia 204 a una llamada anonima con la clave publicable, o sea que
-- cualquiera podia FABRICAR avisos dentro de la intranet. `revoke from public`
-- no bastaba: Supabase concede EXECUTE a `anon` y `authenticated` por privilegio
-- por defecto del esquema, y un revoke a PUBLIC no anula una concesion directa.
-- Hay que nombrarlos.
--
-- Los disparadores siguen funcionando porque son SECURITY DEFINER y propiedad de
-- postgres: llaman a esta funcion como postgres, no como quien guarda.
revoke execute on function public.anotar_aviso(text,text,text,text,uuid,text)
  from anon, authenticated, public;

-- `marcar_notificaciones_leidas` si la llama la gente, pero solo debe poder
-- quien tiene sesion: para `anon`, auth.uid() es nulo y no tocaba ninguna fila,
-- pero devolvia 200 y eso invita a probar.
revoke execute on function public.marcar_notificaciones_leidas() from anon;

delete from public.notificaciones where titulo = 'INTRUSO' and tipo = 'x';;
