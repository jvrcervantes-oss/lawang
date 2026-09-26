-- Frontera frontend/backend — contratos, pieza 5, paso B (26-sep-2026, LAW-336; plan corregido por la
-- revisión previa #120). SOLO AÑADE: dos funciones y tres columnas; el revoke de UPDATE sobre
-- contrato_firmas va aparte, con OK del owner, cuando la pantalla servida ya no escriba directo.
--
-- 1) contrato_firmas_anula: la pantalla hacía `update contrato_firmas set estado='anulado'` en tres
--    sitios (Editar, nuevo enlace de firma, cierre con PDF manual) y no quedaba quién ni por qué.
--    Ahora lo hace el servidor, con el permiso de la policy de hoy dentro, y deja quién/cuándo/motivo.
--    Legal (#120, ALTA): una firma YA DADA no se anula desde aquí — el cambio de un contrato que alguien
--    firmó va por adenda; solo un super admin puede anularla (0 casos en la historia, medido 26-sep).
--    No se borra nada: la fila y su snapshot se quedan como prueba.
-- 2) contrato_poder_vincula: al guardar un Poder Notarial la pantalla buscaba «los contratos de este
--    otorgante» y les ponía `poder_id` en bloque, con la lista de ids decidida en el navegador. Ahora el
--    servidor busca él mismo, con el MISMO criterio que la pantalla (pasaporte o email del Adquiriente I,
--    no el array `compradores`: eso engancharía el poder a contratos donde el otorgante es co-comprador),
--    y solo sobre contratos que quien llama podía editar según la policy de UPDATE.
--    Lee `datos_fields` (columna de 210000, sin descomprimir el `datos` entero); `valida_poder_id` sigue
--    comprobando fila a fila que el poder es del mismo comprador.

alter table public.contrato_firmas
  add column if not exists anulado_en     timestamptz,
  add column if not exists anulado_por    text,
  add column if not exists anulado_motivo text;

comment on column public.contrato_firmas.anulado_motivo is
  'editar | nuevo_enlace | cierre_manual — lo escribe contrato_firmas_anula (26-sep-2026)';

create or replace function public.contrato_firmas_anula(p_contrato uuid, p_motivo text,
                                                        p_incluir_firmadas boolean default false)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_n int;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  -- mismo predicado que la policy «agentes actualizan firmas»
  if not public.es_agente() or not exists (
       select 1 from public.contratos c
        where c.id = p_contrato and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))) then
    raise exception 'No puedes anular las firmas de este contrato' using errcode = '42501';
  end if;
  if v_motivo is null or v_motivo not in ('editar', 'nuevo_enlace', 'cierre_manual') then
    raise exception 'Motivo de anulación no válido' using errcode = '22023';
  end if;
  if coalesce(p_incluir_firmadas, false) and not public.es_super_admin() then
    raise exception 'Una firma ya dada no se anula: el cambio va por adenda (o lo reabre un super admin)'
      using errcode = '42501';
  end if;

  update public.contrato_firmas f
     set estado = 'anulado', anulado_en = now(), anulado_por = (select auth.email()), anulado_motivo = v_motivo
   where f.contrato_id = p_contrato
     and (f.estado = 'pendiente' or (coalesce(p_incluir_firmadas, false) and f.estado = 'firmado'));
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.contrato_firmas_anula(uuid, text, boolean) from public, anon;
grant execute on function public.contrato_firmas_anula(uuid, text, boolean) to authenticated;

create or replace function public.contrato_poder_vincula(p_poder uuid)
returns text[]
language plpgsql security definer set search_path = '' as $$
declare
  v_ids  text[];
  v_nums text[];
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public.puede('contratos')) then
    raise exception 'No tienes acceso a Contratos' using errcode = '42501';
  end if;

  select array_remove(array[
           nullif(lower(btrim(p.datos_fields->>'adq1_pasaporte')), ''),
           nullif(lower(btrim(p.datos_fields->>'adq1_email')), '')], null)
    into v_ids
    from public.contratos p
   where p.id = p_poder and p.tipo = 'poa' and public.contrato_visible(p.creado_por, p.proyecto_id);
  if not found then
    raise exception 'Ese Poder Notarial no existe o no lo puedes ver' using errcode = '42501';
  end if;
  if coalesce(array_length(v_ids, 1), 0) = 0 then return '{}'; end if;

  with hechos as (
    update public.contratos c
       set poder_id = p_poder
     where c.tipo <> 'poa' and c.poder_id is null and c.id <> p_poder
       and (nullif(lower(btrim(c.datos_fields->>'adq1_pasaporte')), '') = any (v_ids)
            or nullif(lower(btrim(c.datos_fields->>'adq1_email')), '') = any (v_ids))
       and public.contrato_visible(c.creado_por, c.proyecto_id)
       -- mismo predicado que la policy de UPDATE de contratos
       and (public.es_super_admin()
            or (coalesce(c.bloqueado, false) = false
                and not public.contrato_firma_viva(c.id)
                and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))
                and public.puede_proyecto_de(jsonb_build_object('fields', c.datos_fields),
                                             c.proyecto_nombre, c.proyecto_id)))
    returning c.numero)
  select coalesce(array_agg(numero order by numero), '{}') into v_nums from hechos;
  return v_nums;
end $$;
revoke all on function public.contrato_poder_vincula(uuid) from public, anon;
grant execute on function public.contrato_poder_vincula(uuid) to authenticated;
