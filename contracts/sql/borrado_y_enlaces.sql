-- ============================================================================
-- Borrado con permisos + documentación por enlace + precios en el inventario
-- 31-jul-2026
-- ----------------------------------------------------------------------------
-- Hasta hoy NADIE podía borrar: `contratos` y `facturas` tenían policies de
-- SELECT/INSERT/UPDATE y ninguna de DELETE, y sin policy la RLS deniega. Lo que
-- pidió el owner:
--   · contratos  → el super admin siempre; cada operador los SUYOS si no están
--                  bloqueados (bloqueado = firmado y sellado).
--   · facturas   → solo administradores y super admin.
--   · documentos → solo super admin.
-- ============================================================================

-- ---- quién es super admin --------------------------------------------------
-- `es_admin()` ya existe y cubre admin + super_admin. Hace falta el escalón de
-- arriba porque el owner separó explícitamente los dos casos.
create or replace function public.es_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo
                    and u.rol = 'super_admin')
$$;

-- ---- las claves ajenas tienen que dejar borrar -----------------------------
-- Sin esto el borrado falla por integridad referencial y el usuario ve un error
-- de base de datos sin saber por qué. Los dos que faltaban:
--   · `contrato_documentos` es la TABLA PUENTE contrato↔documento: al borrar el
--     contrato se va el vínculo, no el documento (que cuelga de `documents`,
--     y ese ya estaba en SET NULL).
--   · `contrato_padre_id` es el enlace reserva→obra: el hijo SOBREVIVE y pierde
--     el vínculo. Con CASCADE, borrar una reserva se llevaría por delante el
--     contrato de construcción, que es un documento distinto y probablemente
--     firmado.
alter table public.contrato_documentos
  drop constraint if exists contrato_documentos_contrato_id_fkey;
alter table public.contrato_documentos
  add constraint contrato_documentos_contrato_id_fkey
  foreign key (contrato_id) references public.contratos(id) on delete cascade;

alter table public.contratos
  drop constraint if exists contratos_contrato_padre_id_fkey;
alter table public.contratos
  add constraint contratos_contrato_padre_id_fkey
  foreign key (contrato_padre_id) references public.contratos(id) on delete set null;

-- ---- borrar contratos ------------------------------------------------------
-- NO se usa `es_suyo()` aquí a propósito, aunque exista: `es_suyo(null)`
-- devuelve TRUE, y los contratos anteriores al 27-jul tienen `creado_por` a
-- NULL. Con ese helper, cualquier agente podría borrar los 15 contratos
-- históricos. Para borrar se exige autoría ESTRICTA; lo demás, super admin.
drop policy if exists "borrar contratos" on public.contratos;
create policy "borrar contratos" on public.contratos
  for delete to authenticated
  using (
    public.es_super_admin()
    or (coalesce(bloqueado, false) = false
        and public.es_agente() and public.puede('contratos')
        and creado_por is not null
        and creado_por = (select auth.email()))
  );

-- ---- borrar facturas -------------------------------------------------------
-- Una factura emitida se ANULA, no se borra: borrarla deja un hueco en la serie
-- fiscal que un contable no puede explicar. Por eso el borrado queda en
-- administradores y la herramienta sigue ofreciendo «anular» como acción normal.
drop policy if exists "borrar facturas" on public.facturas;
create policy "borrar facturas" on public.facturas
  for delete to authenticated
  using (public.es_admin());

-- ---- documentación: el FOR ALL se parte por comandos -----------------------
-- El `for all` que tenía dejaba borrar a cualquier agente. Se separa para poder
-- dar el borrado solo al super admin sin quitarle a nadie el resto.
drop policy if exists "agentes gestionan documentacion" on public.documentos_proyecto;
create policy "documentacion: leer" on public.documentos_proyecto
  for select to authenticated using (public.es_agente());
create policy "documentacion: subir" on public.documentos_proyecto
  for insert to authenticated with check (public.es_agente() and public.puede('documentacion'));
create policy "documentacion: editar" on public.documentos_proyecto
  for update to authenticated
  using (public.es_agente() and public.puede('documentacion'))
  with check (public.es_agente() and public.puede('documentacion'));
create policy "documentacion: borrar" on public.documentos_proyecto
  for delete to authenticated using (public.es_super_admin());

-- El fichero va con su ficha: si la ficha solo la borra el super admin, el
-- objeto también, o quedaría ocupando sitio sin nadie que lo liste.
drop policy if exists "documentacion: agentes borran" on storage.objects;
create policy "documentacion: super admin borra" on storage.objects
  for delete to authenticated
  using (bucket_id = 'documentacion' and public.es_super_admin());

-- ============================================================================
-- Documentación por ENLACE (Google Drive) además de por fichero
-- ----------------------------------------------------------------------------
-- Un dossier pasa de 50 MB y el plan Free da 1 GB en total, con ~60 días de
-- margen al ritmo actual (ver uso_almacenamiento). Los ficheros pesados van a
-- la cuenta de Google Workspace, que ya está pagada, y aquí queda el enlace:
-- el índice sigue siendo uno solo —se busca en el mismo sitio— pero el peso no
-- se come el espacio que necesitan los contratos firmados.
-- ============================================================================
alter table public.documentos_proyecto add column if not exists url text;
alter table public.documentos_proyecto alter column path drop not null;

-- Exactamente uno de los dos. Sin esto cabe una fila con ninguno (un documento
-- que no se puede abrir) o con los dos (dos verdades sobre el mismo documento).
alter table public.documentos_proyecto
  drop constraint if exists documentos_proyecto_fichero_o_enlace;
alter table public.documentos_proyecto
  add constraint documentos_proyecto_fichero_o_enlace
  check ((path is not null) <> (url is not null));

-- ============================================================================
-- Precios por parcela = INVENTARIO, no un PDF
-- ----------------------------------------------------------------------------
-- El owner quiere "meter la tabla de precios y que la gente pueda consultarlos".
-- Eso ya tiene casa: `unidades` (código, proyecto, tipo, superficie, precio,
-- estado) y su herramienta `/unidades/`. No se monta un visor de precios nuevo;
-- se cargan las parcelas ahí y se consultan donde ya se consulta el inventario,
-- que además es lo que cruza con los contratos por `contrato_id`.
-- Faltaba el desglose que sí trae la tabla del cliente: suelo y construcción.
-- ============================================================================
alter table public.unidades add column if not exists precio_suelo numeric;
alter table public.unidades add column if not exists precio_construccion numeric;
comment on column public.unidades.precio is
  'Precio total. Si hay desglose, debe cuadrar con precio_suelo + precio_construccion.';

-- El modelo de villa NO cabe en `tipo`: ese campo dice qué ES la unidad
-- (parcela/villa/apartamento/local) y su CHECK no admite 'Dune' ni 'Dream'.
-- Una parcela de Palm Field es tipo 'parcela' Y lleva asignado un modelo.
alter table public.unidades add column if not exists modelo text;

-- 🔴 `codigo` era UNIQUE a secas, o sea único en TODA la base. Palm Field
-- empieza en A1 y Bonian Village también tiene A5, A7 y B7 (están en contratos
-- reales): con la restricción global, cargar el segundo proyecto habría fallado
-- —o peor, habría empujado a inventar códigos que no son los que usa el cliente.
-- Un código de parcela es único DENTRO de su proyecto, no fuera.
alter table public.unidades drop constraint if exists unidades_codigo_key;
alter table public.unidades drop constraint if exists unidades_proyecto_codigo_key;
alter table public.unidades add constraint unidades_proyecto_codigo_key unique (proyecto, codigo);
