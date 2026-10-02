-- destructivo-ok: no destruye nada. «delete/truncate/drop» aparecen solo en REVOKE y en el trigger que IMPIDE borrar o vaciar correo_plantillas.
-- AJUSTES DEL ERP · S5.1: plantillas de correo editables. 2-oct-2026.
-- Encargo: encargos/20260930_erp_ajustes_pantalla.md → «Plan de S5» (revisión previa #191, Seguridad + Datos).
-- Pareja: erp/migraciones/20261002100000_correo_plantillas.sql (maestro). El CONTENIDO es idéntico en los dos repos
-- (erp/test_canon_envia_correo.py lo comprueba); no nombra ningún rol lector porque la tabla no se lee desde el navegador.
--
-- Qué es: el TEXTO de 8 correos que un tercero lee con texto de cortesía (enlace de firma de la cadena, las tres copias del contrato
-- firmado, el aviso de anulación y las tres facturas automáticas) pasa de estar escrito dentro de cada llamante a una fila editable
-- por el super admin. La edge `envia-correo` COMPONE el correo (datos de la base + este texto); el llamante solo manda la clave y los ids.
--
-- El dato tiene un dueño:
--   · el TEXTO es de `correo_plantillas` (una fila por clave, sembrada aquí; nadie crea ni borra filas). `activa=false` y sin texto = usa
--     el texto de FÁBRICA, que vive en supabase/functions/envia-correo/plantillas_fabrica.ts (de cada repo, fuera del canon).
--   · el CATÁLOGO de variables (`variables`, columna SELLADA por trigger) es el único sitio donde se dice qué variables admite cada
--     clave y cuáles son obligatorias. La RPC, la edge de guardado y el motor leen ESTA columna; ninguno la copia.
--   · los DATOS (importes, fechas, números, enlaces) no se guardan aquí ni los pone el texto: los lee la edge de contratos/facturas.
--   · lo que quedó de cada envío es `correos_enviados.plantilla` + `plantilla_version` («v3» = la fila editada, «f:ab12cd34» = fábrica);
--     NUNCA el texto renderizado (puede llevar un enlace con token: LAW-343).
--
-- Decisiones (cada una con su porqué):
--   1. Solo escribe el super admin y SOLO por la edge `plantillas-guardar`: la tabla no tiene ningún permiso para public/anon/
--      authenticated, y la RPC solo la ejecuta service_role. La RPC no se fía de la edge: recibe el uuid del actor y comprueba ELLA que
--      es un super admin activo (service_role no tiene auth.uid()). Un super admin pasa siempre la herramienta «ajustes» (`puede()`
--      devuelve true para él), así que no hay segunda comprobación de herramienta.
--   2. La RPC solo hace UPDATE: las 8 filas existen desde aquí. Un trigger impide cambiar la clave y el catálogo, y borrar o vaciar.
--   3. Texto plano: la RPC repite las reglas de valida.ts → validaTextoPlantilla (sin HTML, sin URLs ni correos sueltos, solo
--      `{{variable}}`, solo variables permitidas, todas las obligatorias). Dos implementaciones de la misma regla: la prueba
--      plantillas_motor.test.js y prueba_correo_plantillas.sql fallan si se separan.
--   4. El historial va a `ajustes_log` en la MISMA transacción (tabla = 'correo_plantillas'): antes/después del texto (son plantillas,
--      no datos de nadie) y el correo del actor.
--   5. Sin policy de lectura: la edge lee con la clave de servicio. Si S5.5 necesita leer desde la pantalla, será por una RPC `*_datos`.

-- ── 1. La tabla ──────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.correo_plantillas (
  clave          text primary key check (clave in ('enlace_firma_cadena', 'copia_firmada_comprador', 'copia_firmada_portal', 'copia_firmada_manual',
                                                   'aviso_anulacion', 'factura_primer_hito', 'proforma_total', 'factura_vencimiento')),
  activa         boolean not null default false,
  asunto         text,
  cuerpo         text,
  cuerpo_alt     text,
  variables      jsonb not null,
  version        integer not null default 0 check (version >= 0),
  actualizado_en timestamptz not null default now(),
  actualizado_por text,
  constraint correo_plantillas_texto_junto check ((asunto is null) = (cuerpo is null)),
  constraint correo_plantillas_activa_con_texto check (not activa or (asunto is not null and cuerpo is not null)),
  constraint correo_plantillas_topes check (char_length(asunto) <= 200 and char_length(cuerpo) <= 5000 and char_length(cuerpo_alt) <= 5000),
  constraint correo_plantillas_variables_forma check (jsonb_typeof(variables -> 'permitidas') = 'array'
    and jsonb_typeof(variables -> 'obligatorias') = 'object' and (variables ->> 'variantes') in ('1', '2'))
);
comment on table public.correo_plantillas is
  'Texto editable de 8 correos (2-oct-2026). Una fila por clave, sembrada; solo UPDATE por correo_plantilla_guardar (service_role, edge plantillas-guardar). activa=false y sin texto = texto de fábrica. variables = catálogo sellado.';
alter table public.correo_plantillas enable row level security;
revoke all on public.correo_plantillas from public, anon, authenticated, service_role;
grant select on public.correo_plantillas to service_role;

-- ── 2. Siembra: las 8 claves con su catálogo sellado (sin texto = fábrica) ────────────────────────────────────────
-- Formato de cada fila, que lee plantillas_fabrica.test.js: ('clave', '{json}'::jsonb)
insert into public.correo_plantillas (clave, variables) values
  ('enlace_firma_cadena',     '{"permitidas":["saludo","numero","enlace","marca"],"obligatorias":{"asunto":["numero"],"cuerpo":["enlace"],"cuerpo_alt":[]},"variantes":1}'::jsonb),
  ('copia_firmada_comprador', '{"permitidas":["saludo","numero","contrato_proyecto","marca"],"obligatorias":{"asunto":["numero"],"cuerpo":["contrato_proyecto"],"cuerpo_alt":[]},"variantes":1}'::jsonb),
  ('copia_firmada_portal',    '{"permitidas":["saludo","numero","contrato_proyecto","portal","marca"],"obligatorias":{"asunto":["numero"],"cuerpo":["contrato_proyecto","portal"],"cuerpo_alt":[]},"variantes":1}'::jsonb),
  ('copia_firmada_manual',    '{"permitidas":["saludo","numero","marca"],"obligatorias":{"asunto":["numero"],"cuerpo":["numero"],"cuerpo_alt":[]},"variantes":1}'::jsonb),
  ('aviso_anulacion',         '{"permitidas":["saludo","numero","bloque_motivo","marca"],"obligatorias":{"asunto":["numero"],"cuerpo":["numero"],"cuerpo_alt":["numero","bloque_motivo"]},"variantes":2}'::jsonb),
  ('factura_primer_hito',     '{"permitidas":["saludo","factura","numero","concepto","importe","marca"],"obligatorias":{"asunto":["factura","numero"],"cuerpo":["factura","numero","concepto","importe"],"cuerpo_alt":[]},"variantes":1}'::jsonb),
  ('proforma_total',          '{"permitidas":["saludo","factura","numero","importe","marca"],"obligatorias":{"asunto":["factura","numero"],"cuerpo":["factura","numero","importe"],"cuerpo_alt":[]},"variantes":1}'::jsonb),
  ('factura_vencimiento',     '{"permitidas":["saludo","factura","numero","fecha","concepto","importe","marca"],"obligatorias":{"asunto":["factura","numero","fecha"],"cuerpo":["factura","numero","fecha","concepto","importe"],"cuerpo_alt":[]},"variantes":1}'::jsonb)
on conflict (clave) do nothing;

-- ── 3. Sellado: la clave y el catálogo no cambian; las filas no se borran ni se vacían ───────────────────────────
create or replace function public._trg_correo_plantillas_sellado() returns trigger
  language plpgsql set search_path to ''
  as $$
begin
  if tg_op = 'UPDATE' then
    if new.clave is distinct from old.clave then
      raise exception 'La clave de una plantilla no cambia.' using errcode = '42501', hint = 'plantilla_clave_inmutable';
    end if;
    if new.variables is distinct from old.variables then
      raise exception 'El catálogo de variables de una plantilla está sellado.' using errcode = '42501', hint = 'plantilla_variables_selladas';
    end if;
    return new;
  end if;
  raise exception 'Las plantillas de correo no se borran ni se vacían: se restaura el texto de fábrica.' using errcode = '42501', hint = 'plantilla_no_se_borra';
end $$;
revoke all on function public._trg_correo_plantillas_sellado() from public, anon, authenticated, service_role;
create or replace trigger correo_plantillas_sellado before update or delete on public.correo_plantillas
  for each row execute function public._trg_correo_plantillas_sellado();
create or replace trigger correo_plantillas_sin_truncate before truncate on public.correo_plantillas
  for each statement execute function public._trg_correo_plantillas_sellado();

-- ── 4. Validar un texto (las mismas reglas que valida.ts → validaTextoPlantilla) ─────────────────────────────────
-- Devuelve el PRIMER error (texto para el usuario) o null si el texto vale.
create or replace function public._correo_plantilla_error(p_texto text, p_campo text, p_vars jsonb) returns text
  language plpgsql immutable set search_path to ''
  as $$
declare
  v_max    int := case when p_campo = 'asunto' then 200 else 5000 end;
  v_usadas text[];
  v        text;
begin
  if p_texto is null or btrim(p_texto) = '' then return format('«%s» está vacío', p_campo); end if;
  if char_length(p_texto) > v_max then return format('«%s» admite %s caracteres como máximo', p_campo, v_max); end if;
  if (case when p_campo = 'asunto' then p_texto else replace(p_texto, E'\n', '') end) ~ '[[:cntrl:]]' then
    return format('«%s» no admite caracteres de control%s', p_campo, case when p_campo = 'asunto' then ' ni saltos de línea' else '' end);
  end if;
  if p_texto ~ '[<>]' then return format('«%s» es texto plano: sin < ni >', p_campo); end if;
  if p_texto ~* '(://|\mwww\.|\mmailto:|\mjavascript:|\mdata:)' or p_texto ~ '\S+@\S+\.\S+' then
    return format('«%s» no admite enlaces ni correos: los enlaces los pone el sistema con una variable', p_campo);
  end if;
  select coalesce(array_agg(m[1]), '{}'::text[]) into v_usadas from regexp_matches(p_texto, '\{\{([a-z][a-z0-9_]*)\}\}', 'g') as m;
  if regexp_replace(p_texto, '\{\{[a-z][a-z0-9_]*\}\}', '', 'g') ~ '[{}]' then
    return format('«%s»: las llaves solo se usan en {{variable}}', p_campo);
  end if;
  foreach v in array v_usadas loop
    if not (p_vars -> 'permitidas') ? v then return format('«%s»: la variable {{%s}} no existe para este correo', p_campo, v); end if;
  end loop;
  for v in select jsonb_array_elements_text(p_vars -> 'obligatorias' -> p_campo) loop
    if not v = any (v_usadas) then return format('«%s» tiene que llevar {{%s}}', p_campo, v); end if;
  end loop;
  return null;
end $$;
revoke all on function public._correo_plantilla_error(text, text, jsonb) from public, anon, authenticated, service_role;

-- ── 5. Guardar: solo UPDATE, solo el super admin que la edge ya verificó, con historial en la misma transacción ─────
-- Restaurar fábrica = asunto, cuerpo y cuerpo_alt nulos con p_activa = false.
create or replace function public.correo_plantilla_guardar(
  p_actor uuid, p_clave text, p_asunto text, p_cuerpo text, p_cuerpo_alt text, p_activa boolean, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email text;
  v_old   public.correo_plantillas%rowtype;
  v_err   text;
  v_antes jsonb;
  v_desp  jsonb;
begin
  -- 1. quién: lo primero, antes de mirar nada más
  select u.email into v_email from public.usuarios u where u.user_id = p_actor and u.activo and u.rol = 'super_admin';
  if not found then
    raise exception 'Cambiar las plantillas de correo exige super admin.' using errcode = '42501';
  end if;
  if p_motivo is not null and char_length(p_motivo) > 500 then
    raise exception 'El motivo admite 500 caracteres como máximo.' using errcode = '22023';
  end if;
  if p_activa is null then raise exception 'Falta indicar si la plantilla está activa.' using errcode = '22023'; end if;

  select * into v_old from public.correo_plantillas where clave = p_clave for update;
  if not found then
    raise exception 'La plantilla «%» no existe.', left(coalesce(p_clave, ''), 60) using errcode = '22023', hint = 'clave_desconocida';
  end if;

  -- 2. restaurar fábrica, o texto completo y válido
  if p_asunto is null and p_cuerpo is null then
    if p_activa or p_cuerpo_alt is not null then
      raise exception 'Sin texto la plantilla no puede estar activa: se usa el de fábrica.' using errcode = '22023';
    end if;
  else
    if p_asunto is null or p_cuerpo is null then
      raise exception 'Hacen falta el asunto y el cuerpo.' using errcode = '22023';
    end if;
    v_err := public._correo_plantilla_error(p_asunto, 'asunto', v_old.variables);
    if v_err is null then v_err := public._correo_plantilla_error(p_cuerpo, 'cuerpo', v_old.variables); end if;
    if v_err is null and (v_old.variables ->> 'variantes') = '2' then
      v_err := public._correo_plantilla_error(p_cuerpo_alt, 'cuerpo_alt', v_old.variables);
    end if;
    if v_err is null and (v_old.variables ->> 'variantes') = '1' and p_cuerpo_alt is not null then
      v_err := 'Esta plantilla solo tiene un cuerpo.';
    end if;
    if v_err is not null then raise exception '%', v_err using errcode = '22023', hint = 'texto_no_valido'; end if;
  end if;

  -- 3. sin cambios no hay versión nueva ni historial
  if (v_old.asunto, v_old.cuerpo, v_old.cuerpo_alt, v_old.activa) is not distinct from (p_asunto, p_cuerpo, p_cuerpo_alt, p_activa) then
    return jsonb_build_object('clave', p_clave, 'version', v_old.version, 'activa', v_old.activa, 'cambiado', false);
  end if;

  v_antes := jsonb_build_object('activa', v_old.activa, 'version', v_old.version, 'asunto', v_old.asunto, 'cuerpo', v_old.cuerpo, 'cuerpo_alt', v_old.cuerpo_alt);
  update public.correo_plantillas
     set asunto = p_asunto, cuerpo = p_cuerpo, cuerpo_alt = p_cuerpo_alt, activa = p_activa,
         version = v_old.version + 1, actualizado_en = now(), actualizado_por = v_email
   where clave = p_clave;
  v_desp := jsonb_build_object('activa', p_activa, 'version', v_old.version + 1, 'asunto', p_asunto, 'cuerpo', p_cuerpo, 'cuerpo_alt', p_cuerpo_alt);
  insert into public.ajustes_log (tabla, clave, antes, despues, motivo, quien)
  values ('correo_plantillas', p_clave, v_antes, v_desp, nullif(btrim(left(coalesce(p_motivo, ''), 500)), ''), v_email);
  return jsonb_build_object('clave', p_clave, 'version', v_old.version + 1, 'activa', p_activa, 'cambiado', true);
end $$;
revoke all on function public.correo_plantilla_guardar(uuid, text, text, text, text, boolean, text) from public, anon, authenticated;
grant execute on function public.correo_plantilla_guardar(uuid, text, text, text, text, boolean, text) to service_role;

-- ── 6. correos_enviados: qué plantilla y qué versión salieron (nunca el texto) ───────────────────────────────────
-- Columnas NULLABLES: los 27 envíos que hoy no pasan por plantilla (y todo el histórico) quedan con null. No toca el CHECK
-- `correos_con_ancla` (contrato o factura) ni el de `via`.
alter table public.correos_enviados add column if not exists plantilla text;
alter table public.correos_enviados add column if not exists plantilla_version text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'correos_enviados_plantilla_check' and conrelid = 'public.correos_enviados'::regclass) then
    alter table public.correos_enviados add constraint correos_enviados_plantilla_check check (
      (plantilla is null and plantilla_version is null)
      or (plantilla is not null and plantilla_version is not null and plantilla in ('enlace_firma_cadena', 'copia_firmada_comprador', 'copia_firmada_portal', 'copia_firmada_manual',
                        'aviso_anulacion', 'factura_primer_hito', 'proforma_total', 'factura_vencimiento')
          and plantilla_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$'));
  end if;
end $$;
comment on column public.correos_enviados.plantilla is 'Clave de la plantilla de correo con la que salió (S5, 2-oct-2026); null = camino libre (subject/message). Con plantilla_version, nunca el texto renderizado: puede llevar un enlace con token (LAW-343).';
comment on column public.correos_enviados.plantilla_version is '«v<n>» = la fila editada de correo_plantillas; «f:<8 hex>» = texto de fábrica (SHA-256 de su texto).';
