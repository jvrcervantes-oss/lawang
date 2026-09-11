-- destructivo-ok: DROP+CREATE POLICY son reescrituras completas de la misma
-- policy (patron ya usado en permisos_por_proyecto.sql), sustituidas en la
-- misma sentencia, nunca retiradas sin reemplazo. CREATE OR REPLACE FUNCTION
-- es sustitucion. Cero DELETE/TRUNCATE/RLS off.
-- ════════════════════════════════════════════════════════════════════════════
-- sales_manager/project_manager PUEDEN CREAR Y EDITAR (no solo leer) — 11-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Corrección directa del owner sobre lo construido ayer: "un sales manager es
-- el encargado del proyecto — si un agente se equivoca al hacer algo en su
-- contrato necesito que el manager pueda rectificar sin tener que acudir a un
-- administrador". Revisión previa de Seguridad (11-sep) antes de escribir esto,
-- 5 hallazgos + 1 nota, todos plegados aquí:
--
--   1. `bloqueado=false` NO equivale a "sin firmar" — verificado en vivo: 2
--      contratos reales tienen firma ya `estado='firmado'` en `contrato_firmas`
--      con `bloqueado` todavía en `false`. La policy vieja solo miraba
--      `bloqueado`; se añade `contrato_firma_viva()` (mira `contrato_firmas`
--      de verdad, mismo criterio que ya usa el trigger
--      `contrato_no_editable_en_firma`) — y se aplica a TODOS los editores,
--      no solo al manager: el mismo agujero ya existía para el propio agente.
--   2. Los 7 usuarios sales_manager/project_manager de hoy ya tienen entre 2 y
--      29 proyectos en su array (probablemente de un "Marcar todos" desde
--      /usuarios/, antes de que la asignación se limitara a la ficha de cada
--      proyecto en la corrección anterior de hoy). Esto NO se poda aquí — es
--      dato del owner, no algo que un backend deba decidir en su nombre — pero
--      queda anotado en pendientes.md para que se revise antes de dar por
--      buena la asignación de escritura tan ancha que ya implica.
--   3. `facturas.proyecto_nombre` no se resincronizaba igual que en
--      `contratos` (solo si venía vacío) — se iguala aquí: `trg_espejo_proyecto`
--      ahora sobreescribe SIEMPRE en las dos tablas, mismo criterio, una sola
--      función. Antes de esto solo `contratos` lo hacía incondicionalmente.
--   4. Sin rastro de "un manager corrigió a un agente" — `contrato_evento_log`
--      ya registraba QUIÉN edita (`v_quien`) en cada evento 'editado', pero no
--      si ese quien era el propio autor. Se añade `autor_distinto` al detalle
--      del evento cuando `v_quien` no coincide con `creado_por` — cubre tanto
--      manager-corrige-agente como super_admin-corrige-agente, sin evento
--      nuevo en el CHECK cerrado (menos superficie que tocar).
--   5. `es_suyo(NULL) = TRUE` ya expone 10 contratos y 8 facturas reales a
--      escritura de CUALQUIER agente activo — pero es una decisión YA TOMADA
--      y documentada el 27-jul-2026 (contracts/sql/usuarios_y_permisos.sql):
--      bloquearlas dejaría esos contratos vivos intocables. NO se revierte
--      aquí sin hablarlo con el owner — queda anotado en pendientes.md como
--      una decisión a reconfirmar ahora que también hay managers de por medio,
--      no como un bug que esta tarea deba arreglar por su cuenta.
--   Nota aparte: `recibi_aplicaciones` INSERT ya no comprobaba propiedad en la
--      factura DESTINO (solo en el recibí) — comportamiento previo, no se
--      amplía esa asimetría aquí; solo se añade la rama de manager al lado
--      del recibí, igual que ya hacía `es_suyo`.

-- ── 1. Firma viva de verdad, no solo `bloqueado` ────────────────────────────
create or replace function public.contrato_firma_viva(p_contrato_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select exists (
    select 1 from public.contrato_firmas cf
     where cf.contrato_id = p_contrato_id and cf.estado in ('pendiente', 'firmado'))
$$;
revoke execute on function public.contrato_firma_viva(uuid) from public, anon;
grant execute on function public.contrato_firma_viva(uuid) to authenticated;

-- ── 2. `contratos` — UPDATE: firma-check reforzado + rama de manager ────────
drop policy if exists "el autor o un admin editan contratos no bloqueados" on public.contratos;
create policy "el autor, su manager, o un admin editan contratos sin firma viva" on public.contratos
  for update to authenticated
  using (
    es_super_admin()
    or (
      bloqueado = false and not public.contrato_firma_viva(id)
      and es_agente() and puede('contratos'::text)
      and (es_suyo(creado_por) or public.es_manager_de(proyecto_id))
      and puede_proyecto_de(datos, proyecto_nombre)
    )
  )
  with check (
    es_super_admin()
    or (
      es_agente() and puede('contratos'::text)
      and (es_suyo(creado_por) or public.es_manager_de(proyecto_id))
      and puede_proyecto_de(datos, proyecto_nombre)
    )
  );

-- ── 3. `contratos` — INSERT: además del agente por nombre, el manager por id ─
drop policy if exists "agentes con la herramienta insertan contratos" on public.contratos;
create policy "agentes o su manager insertan contratos" on public.contratos
  for insert to authenticated
  with check (
    es_agente() and puede('contratos'::text)
    and (puede_proyecto_de(datos, proyecto_nombre) or public.es_manager_de(proyecto_id))
  );

-- ── 4. `facturas` — UPDATE: rama de manager (no hay firma en facturas, solo
--       `anulada`, que ya se comprobaba) ────────────────────────────────────
drop policy if exists "el autor o un admin editan facturas no anuladas" on public.facturas;
create policy "el autor, su manager, o un admin editan facturas no anuladas" on public.facturas
  for update to authenticated
  using (
    es_super_admin()
    or (
      (anulada = false) and es_agente() and puede('facturas'::text)
      and (es_suyo(creado_por) or public.es_manager_de(proyecto_id))
    )
  )
  with check (
    es_super_admin()
    or (es_agente() and puede('facturas'::text) and (es_suyo(creado_por) or public.es_manager_de(proyecto_id)))
  );
-- INSERT de facturas no se toca: la policy ya vigente ("agentes con la
-- herramienta insertan facturas") no restringe por proyecto para NINGÚN
-- agente hoy — un manager ya la cumple igual, vía `es_agente()`.

-- ── 5. `recibi_aplicaciones` — INSERT: rama de manager en el lado del recibí ─
drop policy if exists "agentes crean aplicaciones al crear su recibi" on public.recibi_aplicaciones;
create policy "agentes o su manager crean aplicaciones al crear su recibi" on public.recibi_aplicaciones
  for insert to authenticated
  with check (
    es_agente() and puede('facturas'::text)
    and (exists (select 1 from public.facturas r
                  where r.id = recibi_aplicaciones.recibi_id and r.tipo = 'recibi'::text
                    and r.anulada = false
                    and (es_suyo(r.creado_por) or public.es_manager_de(r.proyecto_id))))
    and (exists (select 1 from public.facturas f
                  where f.id = recibi_aplicaciones.factura_id and f.tipo = 'factura'::text
                    and f.anulada = false))
  );
-- DELETE de recibi_aplicaciones NO se toca: no se pidió poder borrar, solo
-- corregir/crear.

-- ── 6. `facturas.proyecto_nombre` se resincroniza SIEMPRE, igual que en
--       `contratos` (antes solo si venía vacío) ─────────────────────────────
create or replace function public.trg_espejo_proyecto()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_nombre text;
begin
  if new.proyecto_id is null and nullif(btrim(coalesce(new.proyecto_nombre,'')),'') is not null then
    select p.id into new.proyecto_id from public.proyectos p where p.nombre = new.proyecto_nombre;
  end if;

  if new.proyecto_id is not null then
    select p.nombre into v_nombre from public.proyectos p where p.id = new.proyecto_id;
    if v_nombre is not null then
      new.proyecto_nombre := v_nombre;
    end if;
  end if;
  return new;
end
$$;

-- ── 7. Rastro: marcar cuándo quien edita NO es el autor original ────────────
-- Se pliega en el evento 'editado' que YA se registraba (sin CHECK nuevo que
-- tocar): `autor_distinto` responde "¿quién tocó esto y era suyo?" sin
-- adivinar, tanto si lo corrigió un manager como un super_admin.
create or replace function public.contrato_evento_log()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_quien  text;
  v_campos text[];
  v_hitos  boolean;
  v_padre  text;
begin
  v_quien := public._quien_actua();

  if tg_op = 'INSERT' then
    insert into public.contrato_eventos (contrato_id, evento, quien)
    values (new.id, 'creado', coalesce(v_quien, new.creado_por));
    return new;
  end if;

  if old.bloqueado is distinct from new.bloqueado then
    if coalesce(new.bloqueado, false) then
      insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
      values (new.id, 'firmado_del_todo',
              jsonb_build_object('via',
                case when new.pdf_firmado_path like '%\_manual.pdf' escape '\'
                     then 'pdf subido a mano' else 'firma electronica' end),
              v_quien);
    else
      insert into public.contrato_eventos (contrato_id, evento, quien)
      values (new.id, 'desbloqueado', v_quien);
    end if;
  end if;

  if old.tipo is distinct from new.tipo then
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (new.id, 'tipo_cambiado',
            jsonb_build_object('de', old.tipo, 'a', new.tipo), v_quien);
  end if;

  if old.contrato_padre_id is null and new.contrato_padre_id is not null then
    select c.numero into v_padre from public.contratos c where c.id = new.contrato_padre_id;
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (new.id, 'traspaso', jsonb_build_object('colgado_de', v_padre), v_quien);
  end if;

  if old.datos is distinct from new.datos then
    select array_agg(key order by key) into v_campos from (
      select key, a.value as va, b.value as vb
        from jsonb_each(coalesce(old.datos->'fields', '{}'::jsonb)) a
        full join jsonb_each(coalesce(new.datos->'fields', '{}'::jsonb)) b using (key)
    ) s where va is distinct from vb;
    v_hitos := (old.datos->'hitos') is distinct from (new.datos->'hitos');
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (new.id, 'editado', jsonb_strip_nulls(jsonb_build_object(
              'campos',       to_jsonb(v_campos[1:15]),
              'campos_total', case when coalesce(array_length(v_campos,1),0) > 15
                                   then array_length(v_campos,1) end,
              'hitos',        case when v_hitos then true end,
              'autor_distinto', case when v_quien is distinct from old.creado_por then true end
            )), v_quien);
  end if;

  return new;
exception when others then
  raise warning 'contrato_eventos (contratos %): %', tg_op, sqlerrm;
  return new;
end $function$;

-- ── Comprobación (la del catálogo) ──────────────────────────────────────────
--   select polname from pg_policy where polrelid in
--    ('public.contratos'::regclass,'public.facturas'::regclass,
--     'public.recibi_aplicaciones'::regclass);
--   select proname from pg_proc where proname='contrato_firma_viva';
-- Y de comportamiento: DO+rollback (nunca el MCP) — manager de un proyecto
-- edita un contrato SIN firma de otro agente de ESE proyecto (pasa), uno YA
-- firmado aunque bloqueado=false (revienta), uno de OTRO proyecto (revienta).
