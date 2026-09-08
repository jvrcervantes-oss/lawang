-- ============================================================================
-- portal_autoservicio — el acceso al portal deja de concederse a mano
-- ----------------------------------------------------------------------------
-- 8-sep-2026. Hasta hoy, para que un comprador entrara en /portal/ un admin
-- tenía que pulsar «Invitar al portal» en su ficha. El paso se olvidaba y, peor,
-- cuando el correo de invitación no salía (SMTP por defecto de Supabase, ~4/h)
-- el fallo solo vivía en un toast: el 8-sep había 19 accesos concedidos y el
-- único estrenado era la cuenta de pruebas del owner.
--
-- La regla pasa a ser del sistema, no de quien se acuerde:
--   tener ficha de comprador con ese correo + al menos un contrato = acceso.
-- El comprador escribe su correo en /portal/, y si le corresponde se le crea el
-- acceso y se le manda el enlace. Nadie concede nada y no sale ni un correo que
-- el propio cliente no haya pedido.
--
-- Decisiones que hay que respetar al tocar esto:
--
--   · REVOCADO MANDA SOBRE LA REGLA. `portal-invitar` revoca apagando TODAS las
--     filas de ese correo, así que una sola fila con activo=false significa «se
--     le quitó a propósito» y la derivación NO lo resucita. Sin esto, revocar a
--     alguien cuya ficha conserva el correo no serviría de nada.
--
--   · SE EXIGE CONTRATO. 23 de las 128 fichas con correo no tienen ninguno: son
--     interesados, no compradores. Abrirles el portal les enseñaría una pantalla
--     vacía y ampliaría la superficie sin dar nada.
--
--   · EL EQUIPO NO ENTRA POR AQUÍ. Una misma cuenta de Auth no puede ser del
--     equipo y del portal (mismo motivo que el 400 `ese_email_es_del_equipo` de
--     portal-invitar). Y no es un caso raro: el 8-sep hay 8 fichas de comprador
--     con el correo de un compañero — son compañeros que además compran, no
--     datos mal metidos.
--
--   · `portal_accesos` SIGUE SIENDO LA FUENTE ÚNICA de quién ve qué. Esta
--     función solo la SIEMBRA; no se deriva nada al vuelo. Por eso el vínculo
--     manual desde Compradores sigue existiendo y sigue haciendo falta: el 8-sep,
--     5 de los 19 accesos usan un correo distinto al de la ficha (familias, o el
--     comprador que prefiere otro buzón), y eso la regla no lo puede adivinar.
--
--   · La función NO crea la cuenta de Auth ni manda el correo: eso exige
--     service_role y vive en la Edge `portal-acceso`. Aquí solo la decisión.
-- ============================================================================

create or replace function public.portal_autoservicio(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_creadas int  := 0;
  v_activos int  := 0;
begin
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    return jsonb_build_object('elegible', false, 'motivo', 'email_invalido');
  end if;

  if exists (select 1 from public.usuarios u where lower(btrim(u.email)) = v_email) then
    return jsonb_build_object('elegible', false, 'motivo', 'equipo');
  end if;

  if exists (select 1 from public.portal_accesos pa where pa.email = v_email and not pa.activo) then
    return jsonb_build_object('elegible', false, 'motivo', 'revocado');
  end if;

  -- Siembra idempotente: toda ficha con ese correo y con contrato. Se vuelve a
  -- ejecutar en cada entrada a propósito — si al comprador le firman un segundo
  -- contrato con otra ficha, la ve sin que nadie tenga que volver a invitarle.
  insert into public.portal_accesos (email, client_id, activo, creado_por)
  select v_email, c.id, true, 'autoservicio'
    from public.clients c
   where lower(btrim(coalesce(c.email, ''))) = v_email
     and exists (select 1 from public.contrato_compradores cc where cc.client_id = c.id)
  on conflict (email, client_id) do nothing;
  get diagnostics v_creadas = row_count;

  select count(*) into v_activos
    from public.portal_accesos pa where pa.email = v_email and pa.activo;

  if v_activos = 0 then
    return jsonb_build_object('elegible', false, 'motivo', 'sin_ficha');
  end if;

  return jsonb_build_object('elegible', true, 'creadas', v_creadas, 'accesos', v_activos);
end
$$;

comment on function public.portal_autoservicio(text) is
  'Decide si un correo tiene derecho al portal (ficha de comprador con contrato, no del equipo, no revocado) y siembra sus filas en portal_accesos. La llama la Edge portal-acceso con service_role; no crea la cuenta de Auth ni envía nada.';

-- `revoke from public` a secas no cierra una función de Supabase: hay que
-- nombrar también a los roles (aprendido el 4-ago). Aquí NO la necesita
-- `authenticated` — solo la Edge con service_role.
revoke execute on function public.portal_autoservicio(text) from public;
revoke execute on function public.portal_autoservicio(text) from anon;
revoke execute on function public.portal_autoservicio(text) from authenticated;
grant  execute on function public.portal_autoservicio(text) to service_role;
