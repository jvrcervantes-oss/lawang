-- destructivo-ok: los drop trigger if exists solo hacen la migración repetible (los triggers son nuevos); no toca filas.
-- Techos (2ª vuelta, 30-sep-2026) — hallazgos del revisor-codigo sobre 20260930023239. Solo añade.
--
-- 1. [ALTA] El guardado del bloque Techos era una CADENA de RPC (precios + una edición por techo): si una fallaba
--    o se cancelaba la confirmación a mitad, el catálogo quedaba a medias. `modelo_techos_guarda_lote` lo hace
--    en UNA transacción; el aviso LW409 (contratos sin firmar afectados) salta al final y deshace todo: se
--    pregunta una vez y se guarda todo o nada.
-- 2. [MEDIA] «Ningún techo activo bajo la base / sin base no hay techos» (owner, 30-sep) solo se miraba en
--    algunas RPC; `modelo_precios_guarda` podía subir la base sin mover techos o vaciarla. 3. [MEDIA] Retirar o
--    recortar un techo podía dejar un proyecto que vende la casa SIN ningún techo, y el trigger de Construcción
--    exige techo: ese proyecto no podría crear el contrato. Las dos reglas pasan a un CONSTRAINT TRIGGER diferido
--    al commit, que mira el modelo tocado venga por donde venga (modelos, modelo_techos, alcance, modelos_villa):
--    diferido porque modelo_precios_guarda cambia la base ANTES de mover los techos en la misma transacción.

create or replace function public._techos_invariantes_modelo(p_modelo uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_base numeric; v_nombre text; v_mal text;
begin
  if p_modelo is null then return; end if;
  if not exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo) then return; end if;  -- sin variantes: «Ulin»
  select m.precio_construccion, m.nombre into v_base, v_nombre from public.modelos m where m.id = p_modelo;
  if not found then return; end if;
  if exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo and t.activo) then
    if v_base is null then
      raise exception '«%» tiene techos y se ha quedado sin precio base: pon la base (el precio de su techo más barato).', v_nombre using errcode = '23514';
    end if;
    select string_agg(t.nombre || ' (' || t.precio_ahora || ')', ', ') into v_mal
      from public.modelo_techos t where t.modelo_id = p_modelo and t.activo and t.precio_ahora < v_base;
    if v_mal is not null then
      raise exception 'En «%» hay techos por debajo del precio base (%): %. Si quieres un techo más barato, baja antes la base; si subes la base, mueve también los techos.',
        v_nombre, v_base, v_mal using errcode = '23514';
    end if;
  end if;
  select string_agg(p.nombre, ', ' order by p.nombre) into v_mal
    from public.modelos_villa mv join public.proyectos p on p.id = mv.proyecto_id
   where mv.modelo_id = p_modelo
     and not exists (select 1 from public.modelo_techos t
                      where t.modelo_id = p_modelo and t.activo
                        and (t.alcance = 'todos'
                             or exists (select 1 from public.modelo_techo_proyectos tp
                                         where tp.techo_id = t.id and tp.proyecto_id = mv.proyecto_id)));
  if v_mal is not null then
    raise exception 'Con este cambio «%» se quedaría sin ningún techo en: %. Un contrato de Construcción necesita techo: deja al menos uno para ese proyecto.',
      v_nombre, v_mal using errcode = '23514';
  end if;
end $$;
revoke all on function public._techos_invariantes_modelo(uuid) from public, anon, authenticated;

create or replace function public._techos_invariantes_trg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_modelo uuid;
begin
  if tg_table_name = 'modelos' then
    v_modelo := coalesce(new.id, old.id);
  elsif tg_table_name = 'modelo_techo_proyectos' then
    select t.modelo_id into v_modelo from public.modelo_techos t where t.id = coalesce(new.techo_id, old.techo_id);
  else
    v_modelo := coalesce(new.modelo_id, old.modelo_id);
  end if;
  perform public._techos_invariantes_modelo(v_modelo);
  return null;
end $$;
revoke all on function public._techos_invariantes_trg() from public, anon, authenticated;

drop trigger if exists techos_invariantes on public.modelos;
create constraint trigger techos_invariantes after update of precio_construccion on public.modelos
  deferrable initially deferred for each row execute function public._techos_invariantes_trg();
drop trigger if exists techos_invariantes on public.modelo_techos;
create constraint trigger techos_invariantes after insert or update on public.modelo_techos
  deferrable initially deferred for each row execute function public._techos_invariantes_trg();
drop trigger if exists techos_invariantes on public.modelo_techo_proyectos;
create constraint trigger techos_invariantes after insert or delete on public.modelo_techo_proyectos
  deferrable initially deferred for each row execute function public._techos_invariantes_trg();
drop trigger if exists techos_invariantes on public.modelos_villa;
create constraint trigger techos_invariantes after insert or update of modelo_id, proyecto_id on public.modelos_villa
  deferrable initially deferred for each row execute function public._techos_invariantes_trg();

-- p_precios: [{id, precio_ahora, precio_2027}] (como modelo_techos_guarda) · p_ediciones: [{id, cambios}] (como
-- modelo_techo_edita). Todo o nada. Sin p_confirmado, si algún cambio deja fuera contratos sin firmar, LW409 al
-- FINAL con el total (y la transacción entera se deshace).
create or replace function public.modelo_techos_guarda_lote(p_id uuid, p_precios jsonb, p_ediciones jsonb, p_confirmado boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare e jsonb; v_uso int := 0; r jsonb; v_tid uuid;
begin
  if not public.es_admin() then raise exception 'Los techos los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(p_precios, '[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p_ediciones, '[]'::jsonb)) <> 'array' then
    raise exception 'Cambios de techos no válidos' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(p_precios, '[]'::jsonb)) > 0 then
    perform public.modelo_techos_guarda(p_id, p_precios);
  end if;
  for e in select * from jsonb_array_elements(coalesce(p_ediciones, '[]'::jsonb)) loop
    begin
      v_tid := (e->>'id')::uuid;
    exception when others then raise exception 'Techo no válido' using errcode = '22023';
    end;
    if not exists (select 1 from public.modelo_techos t where t.id = v_tid and t.modelo_id = p_id) then
      raise exception 'Alguno de los techos no es de este modelo (o ya no existe): recarga la página' using errcode = '22023';
    end if;
    r := public.modelo_techo_edita(v_tid, e->'cambios', true);
    v_uso := v_uso + coalesce((r->>'contratos_sin_firmar')::int, 0);
  end loop;
  if v_uso > 0 and not coalesce(p_confirmado, false) then
    raise exception '% contrato(s) de Construcción sin firmar llevan techos que retiras o sacas de su proyecto: ya no podrán volver a elegirlos. Conservan su precio congelado.', v_uso
      using errcode = 'LW409', hint = v_uso::text;
  end if;
  return jsonb_build_object('ok', true, 'contratos_sin_firmar', v_uso);
end $$;
revoke all on function public.modelo_techos_guarda_lote(uuid, jsonb, jsonb, boolean) from public, anon;
grant execute on function public.modelo_techos_guarda_lote(uuid, jsonb, jsonb, boolean) to authenticated;

