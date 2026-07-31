-- ============================================================================
-- Borrar una operación entera — 31-jul-2026
-- ----------------------------------------------------------------------------
-- Una "operación" no es un contrato: es el contrato padre, los que cuelgan de
-- él (reserva → bloqueo → obra), sus enlaces de firma y sus facturas. Borrar
-- solo el padre dejaba los hijos huérfanos, los enlaces de firma VIVOS —o sea,
-- alguien con el enlace podía seguir firmando un contrato que ya no existe— y
-- las facturas apuntando al vacío.
--
-- Qué hace con cada cosa, y por qué:
--   · enlaces de firma pendientes  → ANULADOS. Un token vivo de un contrato
--     borrado es un documento que se puede firmar sin que nadie lo vea venir.
--   · facturas emitidas            → ANULADAS, no borradas. Borrarlas deja un
--     hueco en la serie fiscal que un contable no puede explicar; anularlas deja
--     el rastro, que es justo lo que hace falta.
--   · contratos                    → BORRADOS (el padre y sus hijos).
--   · unidades                     → vuelven a `disponible` solas, por el
--     trigger `libera_unidad_sin_contrato`.
--
-- Va en una función y no en la aplicación porque son cuatro pasos que tienen que
-- pasar TODOS o NINGUNO: a mitad de camino queda una operación con las facturas
-- anuladas y los contratos todavía vivos, que es peor que no haber empezado.
-- ============================================================================

create or replace function public.borrar_operacion(p_contrato_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ids      uuid[];
  n_hijos  int;
  n_firmas int;
  n_fact   int;
  bloqueado_ajeno text;
begin
  if not public.es_agente() then
    raise exception 'no autorizado';
  end if;

  -- El padre y sus hijos. Un solo nivel a propósito: hoy la cadena es
  -- reserva → obra y no hay nietos; si algún día los hubiera, es mejor que esto
  -- se quede corto y haya que repetirlo que no que arrastre de más.
  select array_agg(c.id) into ids
    from public.contratos c
   where c.id = p_contrato_id or c.contrato_padre_id = p_contrato_id;
  if ids is null then
    raise exception 'esa operación no existe';
  end if;

  -- El permiso se comprueba contrato a contrato con la MISMA regla que la policy
  -- de borrado: super admin siempre, o el autor si no está bloqueado. Si uno
  -- solo de la cadena no se puede borrar, no se borra nada — media operación
  -- borrada es un destrozo peor.
  if not public.es_super_admin() then
    select c.numero into bloqueado_ajeno
      from public.contratos c
     where c.id = any(ids)
       and (coalesce(c.bloqueado,false) = true
            or c.creado_por is null
            or c.creado_por <> (select auth.email()))
     limit 1;
    if bloqueado_ajeno is not null then
      raise exception 'El contrato % está firmado o es de otra persona: esta operación solo la puede borrar un super admin', bloqueado_ajeno;
    end if;
  end if;

  update public.contrato_firmas set estado = 'anulado'
   where contrato_id = any(ids) and estado in ('pendiente','procesando');
  get diagnostics n_firmas = row_count;

  update public.facturas set anulada = true
   where contrato_id = any(ids) and coalesce(anulada,false) = false;
  get diagnostics n_fact = row_count;

  delete from public.contratos where id = any(ids);
  get diagnostics n_hijos = row_count;

  return jsonb_build_object(
    'contratos_borrados', n_hijos,
    'firmas_anuladas',    n_firmas,
    'facturas_anuladas',  n_fact);
end $$;

revoke all on function public.borrar_operacion(uuid) from public, anon;
grant execute on function public.borrar_operacion(uuid) to authenticated;
