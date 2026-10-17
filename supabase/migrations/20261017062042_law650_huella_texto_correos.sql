-- LAW-650 (17-oct-2026, sesión lawang-mejoras-ux): huella y copia del TEXTO de cada correo de contrato que sale por
-- APLICADA en la viva el 17-oct-2026 como 20261017062042 (agencia-cd, fichero tal cual: sha256 ab8e8f39e4c210ae300e484a5ec3d463955f
-- 5426773f32d9f6861c83b5b1bbf3, sin estas 2 líneas); escrita como 20261017132000. Ensayo VERDE lawang-202610171419-af44269e.
-- send-contract-email. Condición de Seguridad para desplegar esa edge (fila [lawang-correo-libre-destinatarios] de
-- contexto/pendientes.md): el texto lo escribe el navegador y, hasta hoy, de un correo de contrato solo quedaba a quién y
-- con qué asunto. Un «paga a esta otra cuenta» mandado desde el buzón de Lawang no dejaba rastro de lo que decía.
-- Plan: plan_huella_texto.md v3 (revisión previa de Seguridad #424 y de Base de datos, 17-oct).
--
-- SOLO CONSTRUYE: dos columnas que nacen vacías, dos checks sobre ellas y text/plain en el bucket privado. Nada se borra,
-- no hay grants ni policies nuevos (el bucket lo sigue leyendo y escribiendo solo service role; `authenticated` no tiene
-- SELECT sobre correos_enviados desde L5, 20261016112502). Se puede repetir sin efecto.
--
-- · mensaje_sha256: sha256 (hex) de los bytes UTF-8 del `message` completo que salió. En facturas también, aunque
--   `mensaje` siga cortado a 20.000 caracteres (pasado eso, `mensaje` no reproduce la huella; decisión por defecto).
-- · mensaje_path: la copia exacta de ese texto en `correos-enviados`, `contratos/<sha256>.txt`. Solo en correos de contrato:
--   el texto en claro NUNCA va en la columna `mensaje` de un contrato (lleva el enlace de firma con su token).
--   El check ata la ruta a su huella; el `mensaje_sha256 is not null` va dentro porque, sin él, una huella nula hace la
--   comparación NULL y el check pasaría con cualquier ruta (Base de datos, M1).
-- ORDEN: aplicar esto ANTES de desplegar la send-contract-email que escribe estas columnas; esa edge falla cerrada sin ellas.
-- En las instancias del ERP va la migración propia del maestro (sin las columnas de LAW-343 ni el bucket allí), no esta.

set local lock_timeout = '5s';

alter table public.correos_enviados
  add column if not exists mensaje_sha256 text,
  add column if not exists mensaje_path text;

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'correos_mensaje_sha256_formato' and conrelid = 'public.correos_enviados'::regclass) then
    alter table public.correos_enviados add constraint correos_mensaje_sha256_formato
      check (mensaje_sha256 is null or mensaje_sha256 ~ '^[0-9a-f]{64}$');
  end if;
  if not exists (select 1 from pg_constraint
                 where conname = 'correos_mensaje_path_de_su_huella' and conrelid = 'public.correos_enviados'::regclass) then
    alter table public.correos_enviados add constraint correos_mensaje_path_de_su_huella
      check (mensaje_path is null or (mensaje_sha256 is not null and mensaje_path = 'contratos/' || mensaje_sha256 || '.txt'));
  end if;
end $$;

comment on column public.correos_enviados.mensaje_sha256 is
  'sha256 hex de los bytes UTF-8 del message completo enviado (LAW-650). En facturas, mensaje puede ir cortado a 20.000 y no reproducirla.';
comment on column public.correos_enviados.mensaje_path is
  'Copia exacta del texto enviado en el bucket privado correos-enviados (contratos/<sha256>.txt). Solo correos de contrato (LAW-650).';

-- text/plain se UNE a lo que ya admita el bucket (hoy application/pdf); si el bucket no está, se para: sin él la edge no
-- podría guardar la copia y rechazaría todos los correos de contrato. Una lista nula ya lo admite todo: se deja como está
-- (convertirla en lista cerraría el bucket a los tipos que hoy acepta).
do $$
begin
  if not exists (select 1 from storage.buckets where id = 'correos-enviados') then
    raise exception 'falta el bucket correos-enviados (20260927130000): sin él send-contract-email no podría enviar ningún contrato';
  end if;
  update storage.buckets
     set allowed_mime_types = (select array_agg(distinct t order by t)
                                 from unnest(allowed_mime_types || array['application/pdf', 'text/plain']) t)
   where id = 'correos-enviados' and allowed_mime_types is not null;
end $$;

notify pgrst, 'reload schema';
