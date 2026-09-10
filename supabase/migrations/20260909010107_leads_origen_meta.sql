-- Bajada de leads de formularios instantaneos de Meta al CRM (9-sep-2026).
-- Hasta hoy imposible: el token de sistema no tenia `leads_retrieval` y /{form_id}/leads
-- devolvia 403, asi que los 68 leads del 10-ago al 8-sep vivian SOLO en Business Suite.

-- Clave de deduplicacion. Es el id que da Meta a cada envio: unico y estable, asi que la
-- recogida puede ser idempotente (upsert) y repetir una vuelta no duplica filas.
alter table public.leads add column if not exists meta_lead_id text;
create unique index if not exists leads_meta_lead_id_uniq
    on public.leads (meta_lead_id) where meta_lead_id is not null;

-- Procedencia: sin esto un lead de Meta es indistinguible de uno de la web, y no se
-- puede saber que anuncio lo trajo (ni por tanto que creatividad merece mas dinero).
alter table public.leads add column if not exists campaign_id text;
alter table public.leads add column if not exists adset_id   text;
alter table public.leads add column if not exists ad_id      text;
alter table public.leads add column if not exists form_id    text;

-- Respuestas de cualificacion del formulario (presupuesto, plazo...). Va aparte de las
-- columnas de contacto a proposito: Seguridad (revision previa de hoy) advirtio que Meta
-- admite preguntas de texto libre donde un lead puede volver a escribir su telefono o su
-- email, asi que este campo se trata como PII y NUNCA sale por Telegram -- ni entero ni
-- filtrado. Al canal solo van las respuestas de tipo conocido, por lista blanca.
alter table public.leads add column if not exists respuestas jsonb;

-- Que version de la politica de privacidad estaba vigente cuando esa persona envio el
-- formulario (hallazgo de Legal, revision previa de hoy): sin este dato no se puede
-- reconstruir que se le dijo a un lead concreto. Barato ahora, imposible despues.
alter table public.leads add column if not exists politica_version text;

-- destructivo-ok: `alter column email drop not null` NO borra ningun dato -- es un cambio
-- de metadatos que solo permite NULL en adelante; las 32 filas existentes siguen con su
-- email. Lo pide Datos en la revision previa de hoy: los seis formularios actuales piden
-- email, pero Meta no obliga a incluir ese campo, y el dia que Marketing lance uno sin el,
-- el insert reventaria y el lead se perderia de verdad -- el unico punto del flujo que no
-- era idempotente. Se relaja ahora que ya se esta migrando la tabla, no cuando pase.
alter table public.leads alter column email drop not null;

comment on column public.leads.meta_lead_id is
    'id del envio en Meta. Clave de deduplicacion de la recogida automatica (R13).';
comment on column public.leads.respuestas is
    'Respuestas de cualificacion del formulario. PII: nunca sale por Telegram.';;
