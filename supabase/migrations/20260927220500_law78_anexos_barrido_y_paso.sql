-- LAW-78 (27-sep-2026), segunda parte: las dos funciones de servidor que usan los scripts preparados
--   · contracts/tools/anexos_barrido.py      → contrato_anexos_huerfanos
--   · contracts/tools/anexos_a_storage.py    → contrato_anexos_pasa_a_archivo
-- Las dos solo las ejecuta service_role (los scripts). Nadie del navegador las llama: reducir la exposición.
-- Va DESPUÉS de 20260927220000_law78_anexos_contrato_storage.sql (usa su tabla).

-- ── Qué sobra en el archivo de anexos ─────────────────────────────────────────────────────────────────────────────
-- SQL no puede borrar de storage.objects (el objeto se quedaría en el disco): esta función solo LISTA; el barrido
-- borra por la API de Storage y después la fila, en ese orden (al revés, un fallo dejaría un objeto sin nadie que
-- diga que está ahí). Dos clases de sobrante, las dos con más de `p_horas` (48 por defecto: da tiempo a que quien
-- sube un anexo pulse Guardar):
--   'objeto' → un objeto del bucket sin fila: una subida que no llegó a registrarse (o el contrato se borró y
--              `on delete cascade` se llevó sus filas).
--   'fila'   → una fila cuyo anexo no nombra nadie en `datos.annexes` de su contrato: una subida a medias (falló la
--              página 4 y las 1-3 quedaron), un anexo quitado y guardado, o un paso al archivo que no terminó.
--              Solo en contratos SIN bloquear y SIN firma viva: en uno firmado no se toca nada, aunque sobre.
create or replace function public.contrato_anexos_huerfanos(p_horas int default 48)
returns table (tipo text, fila_id uuid, path text)
language sql stable security definer set search_path = '' as $$
  select 'objeto'::text, null::uuid, o.name
    from storage.objects o
   where o.bucket_id = 'contratos-anexos'
     and o.created_at < now() - make_interval(hours => greatest(coalesce(p_horas, 48), 24))
     and not exists (select 1 from public.contrato_anexo_paginas p where p.path = o.name)
  union all
  select 'fila'::text, p.id, p.path
    from public.contrato_anexo_paginas p
    join public.contratos c on c.id = p.contrato_id
   where p.created_at < now() - make_interval(hours => greatest(coalesce(p_horas, 48), 24))
     and not coalesce(c.bloqueado, false)
     and not public.contrato_firma_viva(c.id)
     and not exists (
       select 1 from jsonb_array_elements(case when jsonb_typeof(c.datos->'annexes') = 'array'
                                               then c.datos->'annexes' else '[]'::jsonb end) a
        where a->>'id' = p.anexo_id)
$$;
revoke all on function public.contrato_anexos_huerfanos(int) from public, anon, authenticated;
grant execute on function public.contrato_anexos_huerfanos(int) to service_role;

-- ── Pasar los anexos viejos de UN contrato al archivo (fase b del script de migración) ────────────────────────────
-- `p_mapa` = { "<id viejo>": {"id": "<id nuevo>"} , ... }. El script ya ha subido y registrado las páginas (fase a).
-- Aquí, con la fila del contrato BLOQUEADA para que nadie guarde a la vez, se comprueba cada anexo contra lo que
-- de verdad hay en `datos`: tantas filas como páginas, numeradas 1..N, y la huella de CADA fila igual al sha256 de
-- la página vieja decodificada. Solo si todo cuadra se sustituye el anexo por su ficha {id nuevo, title, on}.
-- Cualquier discrepancia para el contrato entero: no se quita nada.
-- Nunca en un contrato bloqueado o con firma viva (lo firmado no se toca).
create or replace function public.contrato_anexos_pasa_a_archivo(p_contrato uuid, p_mapa jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_bloq boolean; v_ann jsonb; v_nuevo jsonb := '[]'::jsonb; e jsonb; v_id text; v_nid text;
  v_pags int; v_filas int; v_mal int; v_hechos int := 0; k text;
begin
  if p_mapa is null or jsonb_typeof(p_mapa) <> 'object' then raise exception 'Mapa de anexos no válido' using errcode = '22023'; end if;
  select coalesce(c.bloqueado, false), c.datos->'annexes' into v_bloq, v_ann
    from public.contratos c where c.id = p_contrato for update;
  if not found then raise exception 'Ese contrato no existe' using errcode = 'P0002'; end if;
  if v_bloq or public.contrato_firma_viva(p_contrato) then
    raise exception 'Contrato bloqueado o con firma viva: sus anexos no se tocan' using errcode = '23514';
  end if;
  if jsonb_typeof(v_ann) is distinct from 'array' then raise exception 'El contrato no tiene anexos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_mapa) loop
    if not exists (select 1 from jsonb_array_elements(v_ann) a where a->>'id' = k and a->>'auto' is null
                     and jsonb_typeof(a->'pages') = 'array' and jsonb_array_length(a->'pages') > 0) then
      raise exception 'El anexo % no es un anexo viejo con páginas de este contrato', k using errcode = '22023';
    end if;
  end loop;
  for e in select value from jsonb_array_elements(v_ann) loop
    v_id := e->>'id';
    if v_id is null or not (p_mapa ? v_id) then v_nuevo := v_nuevo || jsonb_build_array(e); continue; end if;
    v_nid := p_mapa->v_id->>'id';
    if v_nid is null or v_nid !~ '^ax-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'Id nuevo no válido para %', v_id using errcode = '22023'; end if;
    v_pags := jsonb_array_length(e->'pages');
    select count(*) into v_filas from public.contrato_anexo_paginas p where p.contrato_id = p_contrato and p.anexo_id = v_nid;
    if v_filas <> v_pags then
      raise exception 'El anexo % tiene % páginas y en el archivo hay %', v_id, v_pags, v_filas using errcode = '22023';
    end if;
    -- página a página: número y huella de la página vieja (el base64 detrás de la coma del data URL)
    select count(*) into v_mal
      from jsonb_array_elements_text(e->'pages') with ordinality g(pag, n)
      left join public.contrato_anexo_paginas p on p.contrato_id = p_contrato and p.anexo_id = v_nid and p.n = g.n
     where p.id is null
        or p.sha256 <> encode(sha256(decode(split_part(g.pag, ',', 2), 'base64')), 'hex');
    if v_mal > 0 then
      raise exception 'El anexo %: % página(s) del archivo no son las del contrato', v_id, v_mal using errcode = '22023';
    end if;
    v_nuevo := v_nuevo || jsonb_build_array(jsonb_build_object('id', v_nid, 'title', e->'title',
                                                               'on', coalesce(e->'on', 'true'::jsonb)));
    v_hechos := v_hechos + 1;
  end loop;
  update public.contratos c set datos = jsonb_set(c.datos, '{annexes}', v_nuevo) where c.id = p_contrato;
  return v_hechos;
end $$;
revoke all on function public.contrato_anexos_pasa_a_archivo(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.contrato_anexos_pasa_a_archivo(uuid, jsonb) to service_role;
