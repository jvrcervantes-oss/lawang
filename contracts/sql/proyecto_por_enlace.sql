-- ════════════════════════════════════════════════════════════════════════════
-- EL PROYECTO SE REFERENCIA POR ENLACE, NO POR NOMBRE — 19-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- DECISIÓN DEL OWNER: «compradores y proyectos MANDAN sobre el resto de
-- herramientas en cuanto a su información; si añado un proyecto o parcelas,
-- toda la suite que haga referencia a eso debe actualizarse al momento, ni
-- siquiera preguntar».
--
-- CÓMO ESTABA. `unidades` ya lo hacía bien (`proyecto_id`). `contratos` y
-- `facturas` guardaban SOLO el nombre en texto. `renombrar_proyecto()` propaga
-- ese texto a cinco tablas y hasta respeta los documentos congelados — está
-- bien construida— pero propaga **por igualdad de nombre**: cualquier fila cuyo
-- texto no case exactamente queda huérfana para siempre y nada lo dice.
-- Medido el 19-ago: **13 contratos** apuntan a nombres que ya no existen
-- («Mejan Village», «Palm Field by Balian Hills», «Sumba Hills by SandalWoods»…).
--
-- CÓMO QUEDA:
--   · `proyecto_id` es la referencia. El nombre en texto pasa a ser un ESPEJO:
--     si hay id, el texto se escribe desde el id en cada guardado, así que no
--     puede divergir aunque alguien lo teclee.
--   · Renombrar un proyecto se propaga por ID, y **también si alguien edita la
--     tabla `proyectos` a mano**, no solo desde la RPC.
--   · Y lo que NO case por nombre al migrar se queda con `proyecto_id` nulo:
--     ahí el huérfano se VE, que es justo lo que faltaba.
--
-- ⚠️ Congelado sigue mandando sobre el campo IMPRESO. La columna
-- `proyecto_nombre` —la que lee toda la suite— se actualiza siempre; el
-- `datos.fields.proyecto_nombre` de un contrato firmado o una factura enviada
-- NO se toca: ese es el papel que ya tiene alguien en la mano.

alter table public.contratos add column if not exists proyecto_id uuid references public.proyectos(id);
alter table public.facturas  add column if not exists proyecto_id uuid references public.proyectos(id);
create index if not exists contratos_proyecto_idx on public.contratos (proyecto_id);
create index if not exists facturas_proyecto_idx  on public.facturas  (proyecto_id);

comment on column public.contratos.proyecto_id is
  'Referencia al proyecto. `proyecto_nombre` es su ESPEJO: se escribe desde aqui en cada guardado y no puede divergir. Si es null, el contrato nombra un proyecto que no esta en la tabla — huerfano visible, no silencioso.';

-- ── el espejo: si hay enlace, el texto sale del enlace ──────────────────────
create or replace function public.trg_espejo_proyecto()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text;
begin
  -- 1) sin enlace pero con un nombre que SÍ existe: se ata solo. Así las filas
  --    que hoy nacen bien no dependen de que la pantalla se acuerde del id.
  if new.proyecto_id is null and nullif(btrim(coalesce(new.proyecto_nombre,'')),'') is not null then
    select p.id into new.proyecto_id from public.proyectos p where p.nombre = new.proyecto_nombre;
  end if;

  -- 2) con enlace: el texto es un espejo. En `contratos` es el nombre a secas;
  --    en `facturas` la etiqueta lleva la parcela detrás («Bonian Village — A2»)
  --    y ahí solo se sustituye la parte del proyecto, que es lo que cambia.
  if new.proyecto_id is not null then
    select p.nombre into v_nombre from public.proyectos p where p.id = new.proyecto_id;
    if v_nombre is not null then
      if tg_table_name = 'contratos' then
        new.proyecto_nombre := v_nombre;
      elsif coalesce(new.proyecto_nombre,'') = '' then
        new.proyecto_nombre := v_nombre;
      end if;
    end if;
  end if;
  return new;
end $$;

revoke all on function public.trg_espejo_proyecto() from public, anon, authenticated;

drop trigger if exists trg_espejo_proyecto on public.contratos;
create trigger trg_espejo_proyecto before insert or update of proyecto_id, proyecto_nombre
  on public.contratos for each row execute function public.trg_espejo_proyecto();

drop trigger if exists trg_espejo_proyecto on public.facturas;
create trigger trg_espejo_proyecto before insert or update of proyecto_id, proyecto_nombre
  on public.facturas for each row execute function public.trg_espejo_proyecto();

-- ── renombrar un proyecto llega a toda la suite, al momento ─────────────────
-- Por ID, así que funciona aunque el nombre viejo ya no case, y aunque alguien
-- edite `proyectos` directamente en vez de usar `renombrar_proyecto()`.
create or replace function public.trg_proyecto_renombrado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.nombre is not distinct from old.nombre then return new; end if;

  update public.unidades  set proyecto = new.nombre where proyecto_id = new.id;
  update public.contratos set proyecto_nombre = new.nombre where proyecto_id = new.id;
  -- la etiqueta de la factura lleva la parcela detrás: se cambia solo su parte
  update public.facturas
     set proyecto_nombre = replace(proyecto_nombre, old.nombre, new.nombre)
   where proyecto_id = new.id and proyecto_nombre like old.nombre || '%';

  -- El campo IMPRESO, solo en lo que sigue vivo (misma regla que el resto de la
  -- suite): un contrato firmado o una factura enviada no cambian por detrás.
  update public.contratos c
     set datos = jsonb_set(c.datos, '{fields,proyecto_nombre}', to_jsonb(new.nombre))
   where c.proyecto_id = new.id
     and not coalesce(c.bloqueado, false)
     and c.datos #>> '{fields,proyecto_nombre}' = old.nombre
     and not exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id);

  update public.facturas f
     set datos = jsonb_set(f.datos, '{fields,proyecto_nombre}',
                           to_jsonb(replace(f.datos #>> '{fields,proyecto_nombre}', old.nombre, new.nombre)))
   where f.proyecto_id = new.id
     and not coalesce(f.anulada, false) and not coalesce(f.enviada, false)
     and f.datos #>> '{fields,proyecto_nombre}' like old.nombre || '%';

  return new;
end $$;

revoke all on function public.trg_proyecto_renombrado() from public, anon, authenticated;

drop trigger if exists trg_proyecto_renombrado on public.proyectos;
create trigger trg_proyecto_renombrado after update of nombre on public.proyectos
  for each row execute function public.trg_proyecto_renombrado();

-- ── los que quedan sin enlace se VEN ────────────────────────────────────────
create or replace view public.proyectos_huerfanos as
select 'contrato'::text as tipo, c.numero, c.proyecto_nombre as nombra_a, c.bloqueado as congelado
  from public.contratos c
 where nullif(btrim(coalesce(c.proyecto_nombre,'')),'') is not null and c.proyecto_id is null
union all
select 'factura', f.numero, f.proyecto_nombre, coalesce(f.anulada,false) or coalesce(f.enviada,false)
  from public.facturas f
 where nullif(btrim(coalesce(f.proyecto_nombre,'')),'') is not null and f.proyecto_id is null;

alter view public.proyectos_huerfanos set (security_invoker = true);
grant select on public.proyectos_huerfanos to authenticated;

-- ── medido y probado el 19-ago-2026 ────────────────────────────────────────
-- Backfill (por nombre exacto, y la factura hereda el de SU contrato):
--   61 contratos y 71 facturas atados. Quedan 13 contratos y 20 facturas sin
--   enlace: son justo los que nombran proyectos que ya no existen («Mejan
--   Village», «Palm Field by Balian Hills», «Sumba Hills by SandalWoods»…).
--   No se les inventa un proyecto: se ven en `proyectos_huerfanos` y los decide
--   una persona. Ficha LAW-72.
--
-- ⚠️ El backfill se hizo con `session_replication_role = replica`. Sin eso, el
--   UPDATE masivo dispara `sincroniza_unidad_contrato()` y rebota con «La
--   parcela A5 ya esta asignada al contrato RP00012» — el guardarraíl haciendo
--   su trabajo. Rellenar un enlace es mantenimiento, no una edición de negocio.
--
-- Prueba de propagación, en dos bloques `DO` revertidos:
--   · Renombrar «Soka Village W2» → 12 contratos, 13 unidades y 42 facturas al
--     día en el mismo instante, sin tocar nada más, y los 12 contratos vivos
--     con su campo impreso actualizado.
--   · Renombrar «Sumba Hills», que tiene el contrato FIRMADO CR00021 → la
--     columna que lee la suite pasa a «Sumba Hills — PRUEBA»; el campo impreso
--     de CR00021 se queda en «Sumba Hills». Vivo se actualiza, congelado no.

-- ── recolocación de los huérfanos, 19-ago-2026 (el mapa lo dio el owner) ────
--   Mejan Village                 → Mejan Village S7
--   Palm Field by Balian Hills    → Palm Field W5
--   Sumba Hills by SandalWoods    → Sumba Hills
--   Horizon by Balian Hills       → Horizon S1
--   Horizon S2 by Balian Hills    → Java Sunset S2
--   Tamarind Rise by Balian Hills → Tamarind Rise W3, 3.1 y 3.2
--
-- Y dos contratos que NO tenían proyecto ninguno (RP00047, RP00048) se ataron
-- LEYENDO el inventario: la parcela que retienen —A5 y D5— ya sabe que es de
-- «Sari Village W1, 1.1 & 1.2». No es inferir, es mirar dónde ya estaba escrito.
-- Sus Construcciones (CC00026, CC00027) lo heredaron de su contrato padre.
--
-- Resultado: **78 de 80 contratos con enlace**, y 0 facturas con contrato y sin
-- enlace. Quedan dos, los dos FIRMADOS, sin parcela en el inventario y sin
-- contrato padre — no hay de dónde leerlo y no se inventa: **CR00014** y
-- **CH00001**. Los 11 huérfanos que quedan en `proyectos_huerfanos` son las
-- facturas sin contrato de LAW-38, que no tienen de qué heredar.
--
-- El campo IMPRESO solo se rellenó en los contratos VIVOS. RP00047 está firmado
-- y su documento se queda como estaba, que es la regla de toda la suite.
