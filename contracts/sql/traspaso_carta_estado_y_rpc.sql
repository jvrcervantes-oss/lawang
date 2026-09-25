-- Carta de Reserva → Bloqueo de Parcela cuando la Carta es de OTRO agente —
-- 25-sep-2026, owner: «arreglar el flujo cuando un agente tiene que hacer el
-- bloqueo de parcela pero está bloqueada por la carta de reserva».
-- Revisión previa #91 (Seguridad): OK con 4 cambios, aplicados los 4.
-- ════════════════════════════════════════════════════════════════════════════
-- SÍNTOMA: un agente solo LEE sus propios contratos (policy contrato_visible).
-- Si la Carta la hizo otra persona, el selector de parcela del Bloqueo no podía
-- comprobar que el comprador coincide y pintaba la parcela «ya asignada»,
-- bloqueada — aunque la base (sincroniza_unidad_contrato) sí aceptaba el
-- traspaso al guardar.
--
-- 1) UNA regla, no dos (hallazgo 4 de Seguridad): `traspaso_carta_estado()`
--    decide 'no' | 'sin_datos' | 'otro' | 'ok' con EXACTAMENTE lo que ya hacía
--    el trigger (Bloqueo que entra sobre una Carta; pasaporte/email de
--    contrato_identificadores, que ya quita vacíos). El trigger pasa a llamarla
--    — mismo resultado, mismos mensajes — y la RPC de abajo también, así que
--    la pantalla y la base no pueden volver a divergir.
-- 2) `parcela_traspaso_estado(proyecto, codigo, ids)`: responde sobre UNA
--    parcela por llamada (hallazgo 1), solo si la ocupa una Carta vigente, y
--    devuelve número de la Carta + estado — ningún dato personal. Guardas: sin
--    sesión fuera (hallazgo 2), y el MISMO permiso que la policy de INSERT de
--    contratos (es_agente + puede('contratos') + proyecto que vende o que
--    dirige como manager — hallazgo 3). El «oráculo» (con un email se sabe si
--    una Carta del proyecto es suya) es el que el trigger ya da al guardar;
--    aceptado por Seguridad.

create or replace function public.traspaso_carta_estado(
  p_tipo_nuevo text, p_ids_nuevo text[], p_tipo_ocupa text, p_ids_ocupa text[])
returns text
language sql
immutable
set search_path to ''
as $$
  select case
    when not (p_tipo_nuevo = 'reserva_parcela' and p_tipo_ocupa like 'carta_reserva%') then 'no'
    when coalesce(array_length(p_ids_nuevo, 1), 0) = 0
      or coalesce(array_length(p_ids_ocupa, 1), 0) = 0 then 'sin_datos'
    when p_ids_nuevo && p_ids_ocupa then 'ok'
    else 'otro'
  end
$$;
comment on function public.traspaso_carta_estado(text, text[], text, text[]) is
  'Regla única del traspaso Carta de Reserva → Bloqueo de Parcela: no | sin_datos | otro | ok. La usan sincroniza_unidad_contrato (al guardar) y parcela_traspaso_estado (el selector). 25-sep-2026.';

-- El trigger vivo se parchea en su sitio (no se reescribe de memoria: su
-- fuente en el repo va por detrás de producción). Cada sustitución tiene que
-- casar UNA vez exacta o no se aplica nada.
do $$
declare
  d text := pg_get_functiondef('public.sincroniza_unidad_contrato()'::regprocedure);
  r text[][] := array[
    array[E'  traspaso_ok  boolean;\n',
          E'  traspaso_ok  boolean;\n  estado_tr    text;\n'],
    array[E'traspaso_ok := new.tipo = ''reserva_parcela''\n                 and ocupada_tipo like ''carta_reserva%'';',
          E'estado_tr := public.traspaso_carta_estado(new.tipo, ids_nuevo, ocupada_tipo, ids_ocupa);\n      traspaso_ok := estado_tr <> ''no'';'],
    array[E'      if coalesce(array_length(ids_nuevo, 1), 0) = 0\n         or coalesce(array_length(ids_ocupa, 1), 0) = 0 then',
          E'      if estado_tr = ''sin_datos'' then'],
    array[E'      if not (ids_nuevo && ids_ocupa) then',
          E'      if estado_tr = ''otro'' then']
  ];
  i int;
  n int;
begin
  if position('traspaso_carta_estado' in d) > 0 then
    return;   -- ya aplicado
  end if;
  for i in 1..array_length(r, 1) loop
    n := (length(d) - length(replace(d, r[i][1], ''))) / length(r[i][1]);
    if n <> 1 then
      raise exception 'parche sincroniza_unidad_contrato: el tramo % casa % veces (esperado 1)', i, n;
    end if;
    d := replace(d, r[i][1], r[i][2]);
  end loop;
  execute d;
end $$;

create or replace function public.parcela_traspaso_estado(
  p_proyecto text, p_codigo text, p_ids text[])
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_proy_id uuid;
  v_ids     text[];
  v_numero  text;
  v_tipo    text;
  v_ocupa   text[];
begin
  if (select auth.uid()) is null then
    raise exception 'parcela_traspaso_estado: sin sesión';
  end if;
  select p.id into v_proy_id from public.proyectos p where p.nombre = btrim(p_proyecto);
  if not (public.es_agente() and public.puede('contratos')
          and (public.puede_proyecto(p_proyecto, v_proy_id) or public.es_manager_de(v_proy_id))) then
    raise exception 'parcela_traspaso_estado: sin permiso sobre este proyecto';
  end if;

  -- Mismo criterio que contrato_identificadores: minúsculas, sin espacios, sin vacíos.
  select coalesce(array_agg(distinct lower(btrim(x))), '{}') into v_ids
    from unnest((coalesce(p_ids, '{}'::text[]))[1:20]) x
   where nullif(btrim(x), '') is not null;

  select c.numero, c.tipo, public.contrato_identificadores(c.datos)
    into v_numero, v_tipo, v_ocupa
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.proyecto = btrim(p_proyecto) and u.codigo = btrim(p_codigo)
     and c.liberado_en is null;

  if v_tipo is null or v_tipo not like 'carta_reserva%' then
    return null;   -- libre, o la ocupa algo que no es una Carta: nada que traspasar
  end if;
  return jsonb_build_object(
    'numero', v_numero,
    'estado', public.traspaso_carta_estado('reserva_parcela', v_ids, v_tipo, v_ocupa));
end;
$$;
revoke all on function public.parcela_traspaso_estado(text, text, text[]) from public, anon, authenticated;
grant execute on function public.parcela_traspaso_estado(text, text, text[]) to authenticated;
comment on function public.parcela_traspaso_estado(text, text, text[]) is
  'Selector del Bloqueo: ¿esta parcela, ocupada por una Carta que quizá no puedo leer, se puede traspasar a mi Bloqueo? Una parcela por llamada, sin datos personales, mismo permiso que el INSERT de contratos. 25-sep-2026, revisión previa #91.';
