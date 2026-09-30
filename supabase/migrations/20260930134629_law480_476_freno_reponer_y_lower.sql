-- Migración 20260930134629_law480_476_freno_reponer_y_lower (30-sep-2026). APLICADA en la base por la sesión principal
-- (estaba en supabase/pendientes/PENDIENTE_law480_476_freno_reponer_y_lower.sql; se movió aquí sin cambiar el cuerpo).
-- Verificado 30-sep: la rama «ya pagada y descontada» de _comision_devengo_reponer lanza 22023 y comisiones_evaluar_contrato
-- compara con lower() en la condición fijada. Idempotente: si la marca nueva ya está, no hace nada.
--
-- LAW-480 + LAW-476 (visto bueno condicionado de Administración a F5b/LAW-474).
-- Parche sobre el cuerpo VIVO con marca (la definición viva no es la del .sql del repo): si la marca no está, para.
--
-- LAW-480 · _comision_devengo_reponer: la rama «ya pagada y la negativa ya descontada» (crear una diferencia
--   POSITIVA y su solicitud) nunca se ha ejecutado. Hasta probarla, en vez de crear la diferencia lanza 22023:
--   lo regulariza administración a mano. El resto de la función, sin cambios (el código de la rama queda detrás del raise).
--   OJO: comisiones_evaluar_contrato llama a _comision_devengo_reponer sin capturar excepciones, así que si un
--   contrato cae en esa rama, su recálculo entero falla con 22023 en cada pasada hasta que administración lo regularice.
-- LAW-476 · comisiones_evaluar_contrato: la búsqueda de la condición fijada (v_cond_fija) comparaba el email con
--   mayúsculas; ahora lower() a los dos lados, como el resto de la función.
do $mig$
declare
  v_def text; v_old text; v_new text; v_n int;
begin
  -- LAW-480
  v_def := pg_get_functiondef('public._comision_devengo_reponer(uuid,numeric,jsonb,text)'::regprocedure);
  v_new := E'  if round(v_obj - v_vig, 2) >= 0.01 then\n'
        || E'    raise exception ''Esta comisión ya se pagó y se descontó: la regulariza administración a mano'' using errcode = ''22023'';\n';
  if position('la regulariza administración a mano' in v_def) = 0 then
    v_old := E'  if round(v_obj - v_vig, 2) >= 0.01 then\n';
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_n <> 1 then
      raise exception 'LAW-480: marca encontrada % veces en _comision_devengo_reponer (se esperaba 1)', v_n;
    end if;
    execute replace(v_def, v_old, v_new);
  end if;

  -- LAW-476
  v_def := pg_get_functiondef('public.comisiones_evaluar_contrato(uuid)'::regprocedure);
  v_old := E'\n         and d.beneficiario_email = v_beneficiario\n         and d.nivel = v_nivel\n';
  v_new := E'\n         and lower(d.beneficiario_email) = lower(v_beneficiario)\n         and d.nivel = v_nivel\n';
  if position(v_new in v_def) = 0 then
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_n <> 1 then
      raise exception 'LAW-476: marca encontrada % veces en comisiones_evaluar_contrato (se esperaba 1)', v_n;
    end if;
    execute replace(v_def, v_old, v_new);
  end if;
end $mig$;
