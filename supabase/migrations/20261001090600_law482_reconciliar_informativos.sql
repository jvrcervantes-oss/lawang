-- LAW-482 (1-oct-2026): comisiones_reconciliar y los devengos informativos (closer / setter / team_lead).
-- Un devengo de esos niveles es INFORMATIVO: es el reparto interno del Sales Manager sobre SU bote, nunca un pago de la empresa. La versión
-- viva (171500 + 233000) lo trata como pagable: si no está «pendiente» (p. ej. marcado «pagada»), un cambio de contrato cae en la rama
-- `diferencia` y abre una fila en comisiones_diferencias («la comisión ya estaba pagada: se paga la diferencia»). En Lawang NO abre solicitud de
-- pago (_comision_diferencia_solicitud sale si el nivel no es manager/estandar/propia, 20260928210000:328): solo deja la fila.
-- Arreglo = el del maestro (F9 M5 §3b): su importe se ACTUALIZA en su sitio (rama `actualizar`, con su apunte en comisiones_ajustes_log), sin
-- diferencia. Las ramas `revisar` (ajuste manual, disputa, beneficiario inactivo, subida del mismo equipo…) siguen antes y mandan; manager,
-- estándar y propia no cambian. La subida de un informativo del mismo equipo va a `revisar` y no se auto-aplica: es a propósito, no «arreglarlo».
-- Revisión previa #179 (Administración + Datos, 1-oct-2026). Cambios frente al maestro:
--  · el ancla usa `v_lawang`, no `v_empresa` (nombre de la variable en Lawang);
--  · NO anula las filas de comisiones_diferencias de esos niveles que el bug ya haya abierto: es tocar datos de dinero de producción y espera
--    el OK del owner tras ver las filas reales (ver pendiente LAW-482). Mientras queden vivas, `v_vig` las suma y el informativo afectado volvería a dar delta: si
--    algún día las hay, se anulan ANTES de aplicar esto (hoy no hay ninguna, comprobado el 1-oct).
-- Parche por `replace` sobre la versión VIVA (no se copia su cuerpo): ancla única comprobada (si no aparece exactamente una vez, aborta) e
-- idempotente (marca F9M5-informativo). ROLLBACK: volver a `create or replace` con el cuerpo de 20260930233000_f8_b_reconciliar_pct_congelado.sql.
-- destructivo-ok: no borra ni actualiza datos; solo redefine la función.
do $informativos$
declare
  v_def text := pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure);
  v_ancla constant text := 'elsif r.estado = ''pendiente'' and (not v_lawang or v_sp.estado = ''pendiente'')';
  v_marca constant text := 'F9M5-informativo';
  v_nuevo text;
begin
  if position(v_marca in v_def) > 0 then
    return;   -- ya parcheada
  end if;
  if (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'LAW-482: no encuentro exactamente una vez la rama `actualizar` en comisiones_reconciliar; revisar la version viva antes de parchear'
      using errcode = '55000';
  end if;
  v_nuevo := replace(v_def, v_ancla,
    'elsif r.nivel in (''closer'', ''setter'', ''team_lead'') then' || chr(10)
    || '      v_accion := ''actualizar'';   -- ' || v_marca || ': informativo (nunca un pago de la empresa): se actualiza en su sitio, sin diferencia' || chr(10)
    || '    ' || v_ancla);
  execute v_nuevo;
  if position(v_marca in pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure)) = 0 then
    raise exception 'LAW-482: el parche no quedo aplicado' using errcode = '55000';
  end if;
end
$informativos$;
revoke all on function public.comisiones_reconciliar(uuid, boolean, jsonb) from public, anon, authenticated;
