-- unidad_guarda: cambiar el modelo desde la ficha de la parcela no se guardaba (27-sep-2026).
--
-- La RPC escribia el texto `modelo` pero dejaba `modelo_id` como estaba, y el trigger
-- `trg_espejo_modelo` (BEFORE UPDATE OF modelo_id, modelo) reescribe `modelo` con el nombre
-- del `modelo_id` que haya: el modelo nuevo se pisaba con el viejo sin error. Caso real:
-- SH-103 Dali+ -> Dream el 26-sep; se guardo el precio de Dream (101.000) y el modelo siguio
-- en Dali+. La fuente del modelo es `modelo_id`; el texto es su espejo.
--
-- Cambio: si el texto del modelo cambia, `modelo_id` se vacia y el trigger lo vuelve a
-- resolver por nombre (sin match queda como texto fuera de catalogo, igual que antes).
-- Y el cambio de modelo queda en `unidades_log`: cambia lo que se vende.
-- Resto de la funcion identico a la version viva (20260927011500).

CREATE OR REPLACE FUNCTION public.unidad_guarda(p_id uuid, p_datos jsonb, p_motivo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_old public.unidades%rowtype; v_new public.unidades%rowtype; v_id uuid;
  v_proy uuid; v_admin boolean := public.es_admin();
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_codigo text := nullif(btrim(coalesce(p_datos->>'codigo', '')), '');
  v_nproy text := btrim(coalesce(p_datos->>'proyecto', ''));
  v_mon text := upper(nullif(btrim(coalesce(p_datos->>'moneda', '')), ''));
  v_est text := nullif(btrim(coalesce(p_datos->>'estado', '')), '');
  v_modelo text := nullif(btrim(coalesce(p_datos->>'modelo', '')), '');
  v_sup numeric; v_suelo numeric; v_obra numeric;
  v_dinero boolean;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public.puede('unidades')) then
    raise exception 'No tienes la herramienta Unidades' using errcode = '42501';
  end if;
  if v_codigo is null then raise exception 'El código no puede quedar vacío' using errcode = '22023'; end if;
  if v_mon is not null and v_mon not in ('EUR', 'USD', 'AUD', 'IDR') then raise exception 'Moneda no válida' using errcode = '22023'; end if;
  begin
    v_sup   := nullif(p_datos->>'superficie_m2', '')::numeric;
    v_suelo := nullif(p_datos->>'precio_suelo', '')::numeric;
    v_obra  := nullif(p_datos->>'precio_construccion', '')::numeric;
  exception when others then raise exception 'Revisa superficie y precios: no son números válidos' using errcode = '22023';
  end;
  if coalesce(v_sup, 0) < 0 or coalesce(v_suelo, 0) < 0 or coalesce(v_obra, 0) < 0 then
    raise exception 'Superficie y precios no pueden ser negativos' using errcode = '22023';
  end if;
  if p_datos ? 'moneda' and v_mon is null then raise exception 'La moneda no puede quedar vacía' using errcode = '22023'; end if;
  v_proy := public._unidad_proyecto(v_nproy);

  if p_id is null then
    if v_est is not null and v_est not in ('disponible', 'no_disponible', 'bloqueada') then
      raise exception 'Ese estado no se pone a mano: lo decide el contrato' using errcode = '22023';
    end if;
    insert into public.unidades (codigo, proyecto, tipo, modelo, superficie_m2, precio_suelo, precio_construccion,
                                 moneda, notas, fase_masterplan, zona_masterplan, estado)
    values (v_codigo, v_nproy, coalesce(p_datos->>'tipo', 'parcela'), v_modelo, v_sup,
            case when p_datos ? 'precio_suelo' then v_suelo end, v_obra, coalesce(v_mon, 'EUR'),
            nullif(btrim(coalesce(p_datos->>'notas', '')), ''),
            nullif(btrim(coalesce(p_datos->>'fase_masterplan', '')), ''), nullif(btrim(coalesce(p_datos->>'zona_masterplan', '')), ''),
            coalesce(v_est, 'disponible'))
    returning id into v_id;
    insert into public.unidades_log (unidad_id, antes, despues, via)
    select v_id, null, to_jsonb(u), 'alta' from public.unidades u where u.id = v_id;
    return v_id;
  end if;

  select * into v_old from public.unidades u where u.id = p_id for update;
  if not found or not public.unidad_visible(v_old.proyecto_id) then
    raise exception 'No encuentro esa parcela entre las tuyas' using errcode = '42501';
  end if;
  v_dinero := v_codigo is distinct from v_old.codigo or v_nproy is distinct from v_old.proyecto
           or v_sup is distinct from v_old.superficie_m2
           or (p_datos ? 'precio_suelo' and v_suelo is distinct from v_old.precio_suelo)
           or v_obra is distinct from v_old.precio_construccion
           or coalesce(v_mon, v_old.moneda) is distinct from v_old.moneda;
  if (v_old.contrato_id is not null or v_old.estado in ('reservada', 'vendida', 'cobrada')) and v_dinero then
    if not v_admin then
      raise exception 'Esta parcela tiene contrato: su precio, moneda, superficie, código y proyecto solo los cambia un admin' using errcode = '42501';
    end if;
    if v_motivo is null or length(v_motivo) < 10 then
      raise exception 'Esta parcela tiene contrato: escribe por qué cambias sus datos (queda registrado)' using errcode = '22023';
    end if;
  end if;
  if v_old.contrato_id is not null or (v_old.estado in ('reservada', 'vendida', 'cobrada') and not v_admin) then
    v_est := v_old.estado;
  elsif v_est is null then
    v_est := v_old.estado;
  elsif v_est is distinct from v_old.estado and v_est not in ('disponible', 'no_disponible', 'bloqueada') then
    raise exception 'Ese estado no se pone a mano: lo decide el contrato' using errcode = '22023';
  end if;

  update public.unidades u
     set codigo = v_codigo, proyecto = v_nproy, tipo = coalesce(p_datos->>'tipo', u.tipo),
         modelo = v_modelo,
         -- modelo nuevo -> se suelta el enlace viejo y trg_espejo_modelo lo resuelve por nombre
         modelo_id = case when v_modelo is distinct from v_old.modelo then null else u.modelo_id end,
         superficie_m2 = v_sup,
         precio_suelo = case when p_datos ? 'precio_suelo' then v_suelo else u.precio_suelo end,
         precio_construccion = v_obra,
         moneda = coalesce(v_mon, u.moneda),
         notas = nullif(btrim(coalesce(p_datos->>'notas', '')), ''),
         fase_masterplan = case when p_datos ? 'fase_masterplan' then nullif(btrim(coalesce(p_datos->>'fase_masterplan', '')), '') else u.fase_masterplan end,
         zona_masterplan = case when p_datos ? 'zona_masterplan' then nullif(btrim(coalesce(p_datos->>'zona_masterplan', '')), '') else u.zona_masterplan end,
         estado = v_est
   where u.id = p_id
  returning * into v_new;
  if not public.unidad_visible(v_new.proyecto_id) then
    raise exception 'No trabajas en ese proyecto' using errcode = '42501';
  end if;
  if v_dinero or v_est is distinct from v_old.estado
     or v_new.modelo_id is distinct from v_old.modelo_id or v_new.modelo is distinct from v_old.modelo then
    insert into public.unidades_log (unidad_id, antes, despues, motivo, via)
    values (p_id, to_jsonb(v_old), to_jsonb(v_new), v_motivo, 'ficha');
  end if;
  return p_id;
end $function$;
