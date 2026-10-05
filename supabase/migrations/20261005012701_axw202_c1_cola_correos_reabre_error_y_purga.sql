-- destructivo-ok: redefine tres funciones de la cola de correos creada hoy (create or replace); la purga sigue borrando filas de esa tabla nueva pero ahora CONSERVA las `error`; no se ejecuta aquí ni se toca ningún dato.
-- AXW-202 C1 (5-oct-2026) — dos arreglos de la revisión del propio C1 antes de dar nada por terminado:
--
-- 1. correo_encolar sobre una fila en `error` se tragaba el correo: devolvía {estado:'error', nuevo:false} y no mandaba nada, y quien
--    encola (C2/C3) lo habría leído como «encolado». Es el mismo tropiezo de AXW-127 (20261001160400_encolar_reabre_cancelados).
--    Ahora encolar de nuevo un documento cuya fila está en `error` la REABRE: pendiente, intentos 0, antigüedad y espera a cero
--    (si no, el tope de antigüedad la volvería a cerrar al instante) y despierta a la edge. Una fila `ok` no se reabre (ya se
--    mandó); una `pendiente`/`enviando` tampoco (ya está en camino). Devuelve `reabierto: true`.
--    Consecuencia a tener en cuenta: un llamante que reencola cada día (factura-vencimiento) reabriría cada día las que fallen.
-- 2. La purga de 90 días borraba también las `error` (punto 12 del plan habla de filas TERMINADAS, y un enlace de firma que no
--    salió no debe desaparecer solo, como hace copias_firmadas_purga, que las conserva). Solo `ok` y `cancelado`.
-- 3. correo_cola_salud: `en_error` cuenta los errores de los últimos 30 días (una alarma sin fecha se queda en rojo para
--    siempre tras un solo fallo y se acaba ignorando); pasados 30 días la fila se conserva pero deja de dar la alarma.

create or replace function public.correo_encolar(
  p_clave text, p_firma uuid default null, p_contrato uuid default null, p_factura uuid default null,
  p_vars jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  r      record;
  e      record;
  v      text;
  v_id   uuid;
  v_estado text;
begin
  select * into r from public._correo_cola_regla(p_clave);
  if not found then raise exception 'clave_desconocida' using errcode = '22023'; end if;
  if not r.soportada then raise exception 'clave_no_soportada_aun' using errcode = '22023'; end if;
  if num_nonnulls(p_firma, p_contrato, p_factura) <> 1
     or (r.ancla = 'firma_id'    and p_firma    is null)
     or (r.ancla = 'contrato_id' and p_contrato is null)
     or (r.ancla = 'factura_id'  and p_factura  is null) then
    raise exception 'ancla_invalida' using errcode = '22023';
  end if;
  if p_vars is null or jsonb_typeof(p_vars) <> 'object' then
    raise exception 'vars_invalidas' using errcode = '22023';
  end if;
  for e in select x.key as k, x.value as val from jsonb_each(p_vars) x loop
    v := e.val #>> '{}';
    if not (e.k = any (r.editables)) or jsonb_typeof(e.val) <> 'string'
       or char_length(v) > 120
       or v ~ '[@<>]|https?:|www[.]|[[:cntrl:]]|[A-Za-z0-9._-]{30,}' then
      raise exception 'vars_invalidas' using errcode = '22023';
    end if;
  end loop;

  -- una fila en `error` para este documento: se reabre (volver a pedirlo es querer que salga)
  update public.correos_cola q
     set estado = 'pendiente', intentos = 0, proximo_intento_en = now(), encolado_en = now(),
         error = null, reclamado_hasta = null, vars = p_vars
   where q.clave = p_clave and q.estado = 'error'
     and coalesce(q.firma_id, q.contrato_id, q.factura_id) = coalesce(p_firma, p_contrato, p_factura)
  returning q.id into v_id;
  if v_id is not null then
    perform public._correos_cola_despierta();
    return jsonb_build_object('id', v_id, 'estado', 'pendiente', 'nuevo', false, 'reabierto', true);
  end if;

  insert into public.correos_cola (clave, firma_id, contrato_id, factura_id, vars, prioridad)
  values (p_clave, p_firma, p_contrato, p_factura, p_vars, r.prioridad)
  on conflict (clave, (coalesce(firma_id, contrato_id, factura_id))) where estado <> 'cancelado'
  do nothing
  returning id, estado into v_id, v_estado;

  if v_id is not null then
    perform public._correos_cola_despierta();
    return jsonb_build_object('id', v_id, 'estado', v_estado, 'nuevo', true, 'reabierto', false);
  end if;

  select q.id, q.estado into v_id, v_estado
    from public.correos_cola q
   where q.clave = p_clave and q.estado <> 'cancelado'
     and coalesce(q.firma_id, q.contrato_id, q.factura_id) = coalesce(p_firma, p_contrato, p_factura);
  return jsonb_build_object('id', v_id, 'estado', v_estado, 'nuevo', false, 'reabierto', false);
end $$;

create or replace function public.correos_cola_purga()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.correos_cola q
   where q.estado in ('ok', 'cancelado')
     and coalesce(q.enviado_en, q.encolado_en) < now() - interval '90 days';
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.correo_cola_salud(p_pendiente_min int default 10)
returns table (enviando_atascadas bigint, pendientes_antiguas bigint, en_error bigint, mas_antigua_min bigint)
language sql stable security definer set search_path = '' as $$
  select count(*) filter (where q.estado = 'enviando' and q.reclamado_hasta < now() - interval '11 minutes'),
         count(*) filter (where q.estado = 'pendiente' and q.proximo_intento_en < now() - make_interval(mins => greatest(p_pendiente_min, 1))),
         count(*) filter (where q.estado = 'error' and q.encolado_en > now() - interval '30 days'),
         coalesce(max(extract(epoch from now() - q.encolado_en)::bigint / 60)
                  filter (where q.estado in ('pendiente', 'enviando')), 0)
    from public.correos_cola q
$$;
