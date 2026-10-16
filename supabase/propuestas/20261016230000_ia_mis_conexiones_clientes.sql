-- MCP de Lawang · «apps conectadas» dice también CON QUÉ se conecta (16-oct-2026, sesión mcp-aviso; revisión previa #403).
-- Va DESPUÉS de 20261016073530 (crea public.ia_mis_conexiones) y de 20261016080111. PROPUESTA: no se aplica desde la sesión que
-- la escribe; la revisa la sesión del puente (mcp-abre) y la aplica agencia-cd en su turno. Hasta entonces vive aquí, fuera de
-- migrations/, y la web ya funciona sin ella (ver «Sin esta propuesta»).
--
-- QUÉ CAMBIA (solo construye: create or replace de UNA lectura que ya existe; no crea tablas, no toca datos ni permisos):
--   public.ia_mis_conexiones() devuelve, además de lo que ya devolvía:
--     · `duracion_dias`  la duración de una conexión (ia_ajustes.duracion_dias), para decir «dura 7 días» sin escribirlo a fuego.
--     · `clientes`       los asistentes ACTIVOS (id, asistente, nombre) — SOLO si la IA está encendida y la persona tiene permiso;
--                        si no, []. El id es el «OAuth Client ID» que la persona pega en Claude/ChatGPT al añadir el conector.
--   Nunca devuelve redirect_uris, quién creó el cliente ni los apagados: lo que se necesita para conectar y nada más (§1.ter).
--
-- Por qué. El paso 3 de «Cómo se conecta» (intranet/v4/ia/, ia-conexiones.js) pide el identificador del cliente, y hoy solo lo
-- ve el super admin en Ajustes › IA (ia_ajustes_ver). Un agente con permiso no tenía de dónde sacarlo: invitarle a conectar
-- era mandarle a un callejón (Experiencia, 16-oct). El id de un cliente público OAuth no es un secreto (viaja en la dirección de
-- autorización que abre el propio asistente), pero se da solo a quien puede usarlo.
-- Llamadores con nombre: intranet/v4/assets/ia-conexiones.js (pasos con su botón Copiar; solo los asistentes activos) e
-- intranet/v4/assets/aviso-ia.js (la invitación de la cabecera sale solo si hay ≥1 asistente activo).
-- Sin esta propuesta: la página dice dónde está el identificador (Ajustes › IA) y la invitación solo le sale al super admin,
-- que es el único que lo puede ver. Las dos leen `clientes` en cuanto exista, sin otro cambio de web.
--
-- Dueño y permisos: CREATE OR REPLACE conserva dueño (ia_puente_rol) y EXECUTE (authenticated); postgres puede reemplazarla
-- porque es miembro de ia_puente_rol (20261016073011). El guardián «el puente MCP sigue cerrado» (tools/salud_lawang.py) no
-- cambia: misma firma, mismo dueño, mismos grants. El cuerpo NO es idéntico al de la 073530: se reestructura con dos CTE (`yo`:
-- uid de privado.ia_pantalla_uid(), encendido y duración; `puede`: el permiso) para calcular el permiso una sola vez y usarlo en
-- `clientes`. Es equivalente en lo que ya devolvía: la misma privado.ia_pantalla_uid() (que sigue fallando sin sesión o desde una
-- llamada del asistente: B6/B7), los mismos filtros de conexiones (las de la persona, últimos 30 días) y las mismas claves;
-- comparado con la viva por mcp-abre el 16-oct (prosrc; dueño ia_puente_rol; acl authenticated=X).
-- Prueba: G2, G3 y G4 de supabase/pruebas/mcp_f1_p4_ajustes.sql (sin esta propuesta aplicada salen en rojo como OMITIDAS).
-- ANTES DE APLICAR EN LA VIVA (Seguridad, 16-oct, MEDIA): una rama con 073530 y esta propuesta aplicadas, y esa prueba entera
-- en verde, con B6, B7, G1, G2, G3 y G4. Leer el código no es haberlo probado: es una DEFINER abierta a authenticated.
-- Seguridad dio por aceptable enseñar el id a quien tiene permiso con la IA encendida (la vuelta tiene que estar en
-- redirect_uris y el canje exige PKCE S256: el id solo sirve para que esa persona se conecte ella).
--
-- VUELTA ATRÁS (no destruye nada): volver a crear public.ia_mis_conexiones() tal como está en 20261016073530 (sección 2). La web
-- vuelve sola a «dónde está el identificador» y a la invitación solo para el super admin.

set local lock_timeout = '5s';   -- local: sin él se queda en la sesión del pooler tras apply_migration (mcp-abre, 16-oct)

create or replace function public.ia_mis_conexiones()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with yo as (
    select privado.ia_pantalla_uid() as uid,
           coalesce((select encendido from public.ia_ajustes where id), false) as encendido,
           (select duracion_dias from public.ia_ajustes where id) as duracion_dias
  ), puede as (
    select y.*, exists (select 1 from public.ia_permisos x where x.usuario_id = y.uid and x.quitado_en is null) as permiso
      from yo y
  )
  select jsonb_build_object(
    'encendido', p.encendido,
    'permiso', p.permiso,
    'duracion_dias', p.duracion_dias,
    -- con qué se conecta: solo a quien puede conectar ahora mismo, y solo los asistentes activos
    'clientes', case when p.encendido and p.permiso then coalesce((
      select jsonb_agg(jsonb_build_object('id', k.id, 'asistente', k.asistente, 'nombre', k.nombre) order by k.asistente, k.nombre)
        from public.ia_clientes k where k.activo), '[]'::jsonb) else '[]'::jsonb end,
    'conexiones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'asistente', k.asistente, 'nombre', k.nombre, 'creada_en', c.creada_en, 'expira_en', c.expira_en,
               'viva', c.revocada_en is null and c.expira_en > now(), 'revocada_en', c.revocada_en,
               'revocada_motivo', c.revocada_motivo,
               'ultima_llamada', (select max(l.creado_en) from public.ia_llamadas l where l.conexion_id = c.id),
               'llamadas', (select count(*) from public.ia_llamadas l where l.conexion_id = c.id and l.resultado = 'ok'))
             order by c.creada_en desc)
        from public.ia_conexiones c join public.ia_clientes k on k.id = c.cliente_id
       where c.usuario_id = p.uid and c.creada_en > now() - interval '30 days'), '[]'::jsonb))
    from puede p;
$$;
