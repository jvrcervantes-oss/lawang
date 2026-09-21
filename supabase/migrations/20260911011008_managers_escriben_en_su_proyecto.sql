-- destructivo-ok: DROP+CREATE POLICY son reescrituras completas de la misma
-- policy (patron ya usado en permisos_por_proyecto.sql), sustituidas en la
-- misma sentencia, nunca retiradas sin reemplazo. CREATE OR REPLACE FUNCTION
-- es sustitucion. Cero DELETE/TRUNCATE/RLS off.
-- Razonamiento completo (5 hallazgos de Seguridad, 1 nota) en
-- proyectos/Lawang/contracts/sql/managers_escriben_en_su_proyecto.sql

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

drop policy if exists "agentes con la herramienta insertan contratos" on public.contratos;
create policy "agentes o su manager insertan contratos" on public.contratos
  for insert to authenticated
  with check (
    es_agente() and puede('contratos'::text)
    and (puede_proyecto_de(datos, proyecto_nombre) or public.es_manager_de(proyecto_id))
  );

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
;
