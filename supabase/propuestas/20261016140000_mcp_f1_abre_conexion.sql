-- MCP de Lawang · F1 · abre la entrada del puente: la edge `mcp` (anon) y la página de conexión (authenticated) (16-oct-2026,
-- sesión mcp-lawang). Va DESPUÉS de 20261016080000: ia_peticion_ver nace en la 073530 como ia_peticion_datos y se renombra allí.
-- PARADA DEL OWNER: abre una función a `anon` (CLAUDE.md, Política de autonomía; departamentos/backend/prompt.md → Supabase).
-- No se aplica en la viva sin su OK escrito; hasta entonces vive en supabase/propuestas/ (fuera de migrations/: revisor, 16-oct) y
-- con el OK pasa a migrations/. Sale JUNTO con el despliegue de la edge `mcp` y la página intranet/v4/ia/conectar/: sin ellos
-- estas tres funciones no tendrían llamador (Seguridad, 16-oct; contexto/seguridad_2026.md §1.ter). La página (index.html,
-- ia-conectar.js e ia-conectar.css) espera en supabase/propuestas/web/ con sus rutas de destino: con el OK vuelve a su sitio,
-- se resella (tools/sella_assets.py) y sale en el mismo aterrizaje que esta migración y el despliegue de la edge.
-- Condiciones para el OK (contexto/pendientes.md): aviso por correo a la persona en cada conexión nueva, tope de peticiones `pide`
-- sin conexión (riesgo residual de abuso) y que el OK nombre la lectura de unidades_log (herramienta de cambios de estado).
--
-- Por qué a anon. La edge `mcp` no tiene llaves (ni service_role ni secretos): llega a la base solo con la clave publicable, es
-- decir, como anon. public.ia_puente solo hace algo si le llega un token, un código o una petición válidos (256 bits aleatorios,
-- comprobados por su hash dentro de la base); con cualquier otra cosa devuelve error sin escribir (prueba J3 de
-- supabase/pruebas/mcp_f1_p1_base.sql). Pública con motivo escrito: contexto/seguridad_2026.md §1.ter. Llamador: la edge `mcp`.
-- Cualquiera con la clave publicable puede llamarla también sin la edge; por eso PKCE, recurso, tope y registro viven dentro
-- de la base, no en la edge (#394/#395).
-- Por qué a authenticated. ia_peticion_ver (qué asistente pide entrar) e ia_conexion_autoriza (la persona acepta, con la
-- contraseña puesta hace ≤120 s) las llama la página de conexión con la sesión de la persona; cada una lo comprueba todo por dentro.
-- La contraseña entra aquí en la huella de acceso, en el MISMO fichero que el grant que deja crear conexiones (Seguridad,
-- 16-oct): la 110000 ya no lee ninguna credencial de Auth, así que nunca nace una conexión con la huella sin contraseña. Si el
-- owner no da la marca, es la salida B («cambiar la contraseña no corta las conexiones») decidida por escrito en el encargo,
-- nunca este grant suelto. Si llegara a haber conexiones de antes, cambiar la fórmula las corta en su siguiente llamada:
-- falla cerrado. Prueba: I2b de supabase/pruebas/mcp_f1_p1_base.sql (corre solo si esta propuesta está aplicada).
-- destructivo-ok: lee auth.users.encrypted_password SOLO para sacar un sha256 del hash bcrypt (con su sal: no sirve para adivinar
-- la contraseña), dentro de privado.ia_auth_usuario, que solo ejecuta ia_puente_rol y cuyo resultado nunca llega a una persona ni
-- a un asistente (ia_mis_conexiones no lo devuelve: medido por Seguridad el 16-oct). Necesita la marca del owner.
--
-- VUELTA ATRÁS (no destruye nada):
--   revoke execute on function public.ia_puente(text, jsonb) from anon;
--   revoke execute on function public.ia_conexion_autoriza(text) from authenticated;
--   revoke execute on function public.ia_peticion_ver(text) from authenticated;
--   y volver a crear privado.ia_auth_usuario tal como está en 20261016073011 (corta las conexiones que haya: falla cerrado).
create or replace function privado.ia_auth_usuario(p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'email', u.email,
           'app_metadata', coalesce(u.raw_app_meta_data, '{}'::jsonb),
           'baneado', coalesce(u.banned_until > now(), false),
           -- contraseña (sha256 de su hash) · correo · bloqueo · baja · factores verificados por id
           'huella', encode(sha256(convert_to(coalesce(u.encrypted_password, '') || '|' || coalesce(u.email, '') || '|'
                                              || coalesce(u.banned_until::text, '') || '|' || coalesce(u.deleted_at::text, '') || '|'
                                              || coalesce((select string_agg(f.id::text, ',' order by f.id) from auth.mfa_factors f
                                                            where f.user_id = u.id and f.status = 'verified'), ''), 'UTF8')), 'hex'),
           'factores', (select count(*) from auth.mfa_factors f where f.user_id = u.id and f.status = 'verified'),
           'activo', coalesce((select x.activo from public.usuarios x where x.user_id = u.id), false))
    from auth.users u
   where u.id = p_uid
$$;
-- create or replace conserva dueño (postgres) y EXECUTE (solo ia_puente_rol); se repite por si acaso, sin abrir nada
revoke all on function privado.ia_auth_usuario(uuid) from public, anon, authenticated, service_role;
grant execute on function privado.ia_auth_usuario(uuid) to ia_puente_rol;

grant execute on function public.ia_puente(text, jsonb) to anon;
grant execute on function public.ia_conexion_autoriza(text) to authenticated;
grant execute on function public.ia_peticion_ver(text) to authenticated;
