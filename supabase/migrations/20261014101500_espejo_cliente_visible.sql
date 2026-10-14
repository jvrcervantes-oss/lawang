-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68). El maestro lleva las MISMAS piezas (espeja_comprador,
--   sincronizar_compradores, contratos_tipo_permitido en su linea_base): el porte queda diagnosticado en el informe de Backend del 14-oct.
-- ESPEJO DEL COMPRADOR SOLO SOBRE FICHAS QUE QUIEN GUARDA PUEDE VER + TIPO PERMITIDO TAMBIEN AL EDITAR (14-oct-2026, Backend).
-- Hallazgo vivo de Seguridad (revision previa del 14-oct, solo catalogo), CONFIRMADO leyendo los cuerpos vivos ese dia:
--   · contrato_guarda (DEFINER) acepta en datos.adq1_client_id y en datos.compradores[].client_id el id de CUALQUIER ficha;
--   · trg_espejo_comprador -> espeja_comprador (DEFINER) copia de esa ficha a datos.fields: adq1_nombre, adq1_pasaporte, adq1_email,
--     adq1_telefono, adq1_domicilio, adq1_nacionalidad, adq1_forma_juridica, adq1_registro, adq1_rep_nombre, adq1_rep_cargo, adq1_tipo
--     (11 campos de clients; solo del Adquiriente I; en alta y en cada edicion de un contrato sin firmar y sin firma abierta);
--   · contrato_guarda devuelve 'fields' ya espejado. Ninguna funcion del camino nombraba cliente_visible, ni pasaba por el tope
--     (20 fichas / 10 min) ni por el registro de comprador_ficha;
--   · sincronizar_compradores enlazaba por id sin comprobar, o por pasaporte/correo en toda `clients`.
--   La pantalla YA no lo ofrece desde el 7-oct (comprador_ficha vacio -> «Esa ficha es de otra empresa o de otro comercial»): esto
--   pone en el servidor la regla que la pantalla ya aplica. Recuento sin datos personales (14-oct): 291 contratos con cliente enlazado
--   y autor con usuario; 29 con cliente de otro propietario; 7 cuyo cliente su autor ACTIVO no ve hoy (5 de 3 agentes, 2 de 1 project
--   manager); desde el 7-oct, 0 de agentes.
-- QUE HACE (variante A, la recomendada por Seguridad; la B, «contratar al cliente de otro con tope y registro», esta escrita aparte y
--   SIN aplicar en supabase/reversion_espejo_cliente_visible/VARIANTE_B_contratar_ajeno_con_registro.sql: la regla la decide el owner):
--   1) _cliente_ficha_visible(uuid): LA regla de comprador_ficha en un solo sitio (es_agente + cliente_visible, o contrato enlazado
--      visible para quien no tiene alcance acotado). comprador_ficha pasa a llamarla: «la misma regla» lo es por construccion.
--      NO toca cliente_visible ni nada del traspaso.
--   2) contrato_guarda llama a _contrato_clientes_comprueba(p_id, datos) ANTES de escribir: 42501 con mensaje propio si un client_id
--      NUEVO (adq1 o compradores[]) es de una ficha que quien guarda no ve. Los ids que el contrato YA tenia no se vuelven a mirar:
--      el borrador anterior al cierre se sigue pudiendo guardar (patron LAW-51 punto 4).
--   3) espeja_comprador no copia una ficha que quien guarda no ve (devuelve los datos tal cual; nunca lanza). En un borrador heredado
--      con cliente no visible, por tanto, NO se re-espeja.
--   4) sincronizar_compradores no enlaza una ficha que quien guarda no ve (por id ni por pasaporte/correo): cae en «sin ficha», con el
--      mismo aviso de siempre y ningun dato (un aviso distinto seria un oraculo de pasaportes ajenos). No lanza: corre dentro de
--      trg_sincronizar_compradores, que se traga las excepciones; por eso el 42501 vive en contrato_guarda.
--   5) contratos_tipo_permitido salta tambien en UPDATE OF tipo, solo si el tipo CAMBIA. Sigue aplicando solo a rol = 'agente':
--      sales_manager y project_manager quedan SIN limite de tipos, como hoy (no se cambia; lo decide el CEO/owner).
--   Sin sesion (auth.uid() nulo: service_role, edges, cron) 3) y 4) se comportan como hoy, igual que contratos_tipo_permitido: esos
--   caminos tienen su propia puerta, y `authenticated` no tiene EXECUTE sobre espeja_comprador/sincronizar_compradores ni escritura
--   directa en `contratos` (solo SELECT, medido el 14-oct).
-- LO QUE NO HACE (queda dicho en el informe): no toca los contratos existentes ni sus enlaces; trg_cliente_actualizado sigue refrescando
--   la ficha en los borradores que YA la tienen enlazada cuando su dueno la edita (como mucho 6 borradores hoy); limpiar esos enlaces
--   es borrar datos y lo decide el owner con Legal.
-- NO COMPILADA: no se ejecuta DDL en la base viva sin orden y el ensayo en un Postgres local no se pudo lanzar. Las marcas del
--   parche SI se comprobaron contra el vivo (solo lectura). Su primera ejecucion es la de la rama.
-- contrato_guarda (8,5 KB) y comprador_ficha se PARCHEAN sobre su definicion viva con marca de codigo y raise si no la encuentra
--   (el repo no coincide con el vivo en esas dos, md5 medido el 14-oct); las otras tres si coinciden y van enteras.
-- destructivo-ok: reemplaza funciones (mismo tipo de retorno) y un trigger; el unico delete es de contrato_compradores DENTRO de
--   sincronizar_compradores (retira el enlace de un rol cuando el documento ya nombra a otra persona que no se puede enlazar)
-- REVERTIR: supabase/reversion_espejo_cliente_visible/REVERSION_espejo_cliente_visible.sql (reabre el hallazgo: solo con OK del owner)
-- Prueba: supabase/pruebas/espejo_cliente_visible.sql — crea contratos: SOLO en rama (`erp/rama_prueba.py lawang --lawang <copia>
--   --aplica 20261014101500_espejo_cliente_visible.sql --prueba espejo_cliente_visible.sql`), nunca en la base viva.

-- ============================================================ 1. La regla, en un solo sitio
-- La misma de comprador_ficha (que desde esta migracion la llama). Identidad solo de auth.uid()/auth.email(), via cliente_visible,
-- alcance_restringido y puede_ver_contrato. Si cambia quien ve una ficha, cambia aqui (o en cliente_visible) y vale para las dos.
create or replace function public._cliente_ficha_visible(p_client uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select public.es_agente() and exists (
    select 1 from public.clients c0
     where c0.id = p_client
       and (public.cliente_visible(c0.propietario, c0.id)
            or (not (select public.alcance_restringido())
                and exists (select 1 from public.contrato_compradores cc
                             where cc.client_id = c0.id and public.puede_ver_contrato(cc.contrato_id)))))
$function$;
revoke all on function public._cliente_ficha_visible(uuid) from public, anon, authenticated;

-- La puerta de contrato_guarda. Solo mira los client_id NUEVOS: los que el contrato guardado ya nombraba (columna generada
-- adq1_client_id, datos.compradores[] y contrato_compradores) no se vuelven a comprobar, para que un borrador anterior al cierre se
-- siga pudiendo guardar. Un id que no es de ninguna ficha se ignora, como hoy. Mensaje propio (el de la pantalla desde el 7-oct):
-- no se confunde con «No tienes permiso para guardar este contrato.» ni con el «permission denied» de un GRANT.
create or replace function public._contrato_clientes_comprueba(p_id uuid, p_datos jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_id uuid;
  v_ya uuid[] := '{}'::uuid[];
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if (select auth.uid()) is null then
    return;
  end if;
  if p_id is not null then
    select coalesce(array_agg(q.x), '{}'::uuid[]) into v_ya
      from (select cc.client_id as x from public.contrato_compradores cc where cc.contrato_id = p_id
            union
            select c.adq1_client_id from public.contratos c where c.id = p_id
            union
            select case when btrim(coalesce(e.v->>'client_id', '')) ~ c_uuid then btrim(e.v->>'client_id')::uuid end
              from public.contratos c
             cross join lateral jsonb_array_elements(case when jsonb_typeof(c.datos->'compradores') = 'array'
                                                          then c.datos->'compradores' else '[]'::jsonb end) e(v)
             where c.id = p_id) q
     where q.x is not null;
  end if;
  for v_id in
    select distinct t.x
      from (select case when btrim(coalesce(p_datos->>'adq1_client_id', '')) ~ c_uuid
                        then btrim(p_datos->>'adq1_client_id')::uuid end as x
            union all
            select case when btrim(coalesce(e.v->>'client_id', '')) ~ c_uuid then btrim(e.v->>'client_id')::uuid end
              from jsonb_array_elements(case when jsonb_typeof(p_datos->'compradores') = 'array'
                                             then p_datos->'compradores' else '[]'::jsonb end) e(v)) t
     where t.x is not null
  loop
    continue when v_id = any (v_ya);
    if exists (select 1 from public.clients c where c.id = v_id) and not public._cliente_ficha_visible(v_id) then
      raise exception 'Esa ficha es de otra empresa o de otro comercial: no puedes usarla en un contrato desde tu cuenta. Pídele a un administrador que lo haga.'
        using errcode = '42501';
    end if;
  end loop;
end $function$;
revoke all on function public._contrato_clientes_comprueba(uuid, jsonb) from public, anon, authenticated;

-- ============================================================ 2. El espejo: solo fichas que quien guarda puede ver
create or replace function public.espeja_comprador(p_datos jsonb)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case
    when cl.id is null then p_datos
    else jsonb_set(p_datos, '{fields}',
           coalesce(p_datos->'fields', '{}'::jsonb) ||
           jsonb_strip_nulls(jsonb_build_object(
             'adq1_nombre',         cl.full_name,
             'adq1_pasaporte',      cl.passport_number,
             'adq1_email',          cl.email,
             'adq1_telefono',       cl.phone,
             'adq1_domicilio',      cl.address,
             'adq1_nacionalidad',   cl.nationality,
             'adq1_forma_juridica', cl.forma_juridica,
             'adq1_registro',       cl.registro_num,
             'adq1_rep_nombre',     cl.rep_nombre,
             'adq1_rep_cargo',      cl.rep_cargo,
             'adq1_tipo',           cl.tipo)))
  end
  from (select 1) x
  left join public.clients cl
    on cl.id = case when btrim(coalesce(p_datos->>'adq1_client_id', '')) ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                    then btrim(p_datos->>'adq1_client_id')::uuid end
   and ((select auth.uid()) is null or public._cliente_ficha_visible(cl.id));
$function$;

-- ============================================================ 3. El enlace: igual
create or replace function public.sincronizar_compradores(p_contrato uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_datos  jsonb;
  v_gente  jsonb;
  p        jsonb;
  v_nombre text; v_rol text; v_pas text; v_mail text; v_cid text;
  v_client uuid;
  v_enlaces int := 0;
  v_sin_id text[] := '{}';
  v_sin_ficha text[] := '{}';
  v_roles_vivos text[] := '{}';
  v_borrados int := 0;
begin
  select datos into v_datos from public.contratos where id = p_contrato;
  if v_datos is null then return jsonb_build_object('error', 'contrato inexistente o sin datos'); end if;

  v_gente := jsonb_build_array(jsonb_build_object(
      'rol','adquiriente_1',
      'client_id',    v_datos->>'adq1_client_id',
      'nombre',       v_datos->'fields'->>'adq1_nombre',
      'pasaporte',    v_datos->'fields'->>'adq1_pasaporte',
      'email',        v_datos->'fields'->>'adq1_email',
      'telefono',     v_datos->'fields'->>'adq1_telefono',
      'nacionalidad', v_datos->'fields'->>'adq1_nacionalidad',
      'domicilio',    v_datos->'fields'->>'adq1_domicilio'))
    || coalesce((
      select jsonb_agg(jsonb_build_object(
               'rol','adquiriente_' || (ord + 1),
               'client_id', e->>'client_id',
               'nombre', e->>'nombre', 'pasaporte', e->>'pasaporte', 'email', e->>'email',
               'telefono', e->>'telefono', 'nacionalidad', e->>'nacionalidad',
               'domicilio', e->>'domicilio') order by ord)
      from jsonb_array_elements(
             case when jsonb_typeof(v_datos->'compradores') = 'array'
                  then v_datos->'compradores' else '[]'::jsonb end) with ordinality t(e, ord)
      where ord + 1 <= 9), '[]'::jsonb);

  for p in select value from jsonb_array_elements(v_gente) loop
    v_nombre := btrim(coalesce(p->>'nombre',''));
    continue when v_nombre = '';
    v_rol  := p->>'rol';
    -- Este rol EXISTE en el documento. Se apunta aunque luego no se consiga
    -- enlazar: lo que decide si una fila sobra es el documento, no el enlace.
    v_roles_vivos := v_roles_vivos || v_rol;
    v_pas  := nullif(btrim(coalesce(p->>'pasaporte','')), '');
    v_mail := lower(nullif(btrim(coalesce(p->>'email','')), ''));
    v_cid  := nullif(btrim(coalesce(p->>'client_id','')), '');

    v_client := null;

    if v_cid is not null then
      begin
        select id into v_client from public.clients where id = v_cid::uuid;
      exception when invalid_text_representation then
        v_client := null;
      end;
    end if;

    if v_client is null then
      if v_pas is null and v_mail is null then
        v_sin_id := v_sin_id || v_nombre;
        continue;
      end if;
      if v_pas is not null then
        select id into v_client from public.clients
         where lower(btrim(passport_number)) = lower(v_pas) limit 1;
      end if;
      if v_client is null and v_mail is not null then
        select id into v_client from public.clients
         where lower(email) = v_mail
         order by (tipo = 'persona') desc, created_at
         limit 1;
      end if;
    end if;

    -- 14-oct-2026: con sesion, una ficha que quien guarda NO ve no se enlaza, ni por id ni por pasaporte/correo.
    -- Se trata igual que «sin ficha» (mismo aviso, ningun dato: distinguirlo confirmaria pasaportes ajenos).
    -- El enlace que YA existia a esa misma ficha se conserva (contratos anteriores al cierre); si el rol
    -- estaba enlazado a OTRA persona, ese enlace se retira: el documento ya no la nombra.
    if v_client is not null and (select auth.uid()) is not null
       and not exists (select 1 from public.contrato_compradores x
                        where x.contrato_id = p_contrato and x.rol = v_rol and x.client_id = v_client)
       and not public._cliente_ficha_visible(v_client) then
      delete from public.contrato_compradores x where x.contrato_id = p_contrato and x.rol = v_rol;
      v_client := null;
    end if;

    if v_client is null then
      v_sin_ficha := v_sin_ficha || v_nombre;
      continue;
    end if;

    insert into public.contrato_compradores (contrato_id, client_id, rol)
    values (p_contrato, v_client, v_rol)
    on conflict (contrato_id, rol) do update set client_id = excluded.client_id;
    v_enlaces := v_enlaces + 1;
  end loop;

  /* LOS FANTASMAS. Un contrato que paso de cuatro compradores a dos dejaba
     adquiriente_3 y adquiriente_4 enlazados a las personas de la version
     anterior, y Operaciones los seguia enseñando. Se borran los roles que el
     documento YA NO NOMBRA. Si el documento no nombra a NADIE no se borra nada:
     eso es casi siempre un `datos` a medio escribir, y vaciar la tabla por eso
     convertiria un guardado intermedio en una perdida de enlaces. */
  if array_length(v_roles_vivos, 1) is not null then
    delete from public.contrato_compradores
     where contrato_id = p_contrato
       and rol <> all(v_roles_vivos);
    get diagnostics v_borrados = row_count;
  end if;

  return jsonb_build_object('altas', 0, 'enlaces', v_enlaces,
                            'retirados', v_borrados,
                            'sin_identificador', to_jsonb(v_sin_id),
                            'sin_ficha',         to_jsonb(v_sin_ficha));
end $function$;

-- ============================================================ 4. contrato_guarda y comprador_ficha: parche sobre la definicion VIVA
-- Marcas de codigo puro (sin comentarios), comprobadas contra el vivo el 14-oct (una coincidencia cada una). Idempotente: si ya esta
-- aplicado no hace nada; si la marca no esta (alguien cambio la funcion entre medias) lanza y no se aplica NADA de la migracion.
-- pg_get_functiondef conserva SECURITY DEFINER y search_path; create or replace conserva los permisos (no se abre ni se cierra nada).
do $parche$
declare
  v_def text;
  c_marca constant text := 'v_f := v_datos->''fields'';';
  c_ficha constant text := 'if not exists \(\s*select 1 from public\.clients c0.*?then\s+return;\s+end if;';
begin
  -- contrato_guarda: la comprobacion va tras validar que hay datos y tipo, ANTES de cualquier escritura
  select pg_get_functiondef('public.contrato_guarda(uuid,jsonb)'::regprocedure) into v_def;
  if position('_contrato_clientes_comprueba' in v_def) = 0 then
    if (length(v_def) - length(replace(v_def, c_marca, ''))) / length(c_marca) <> 1 then
      raise exception 'espejo_cliente_visible: la marca de contrato_guarda no aparece exactamente una vez; no se aplica nada';
    end if;
    execute replace(v_def, c_marca, c_marca || E'\n  perform public._contrato_clientes_comprueba(p_id, v_datos);');
  end if;

  -- comprador_ficha: su condicion pasa a ser la funcion unica (mismo texto, ahora en un solo sitio)
  select pg_get_functiondef('public.comprador_ficha(uuid)'::regprocedure) into v_def;
  if position('_cliente_ficha_visible' in v_def) = 0 then
    if (select count(*) from regexp_matches(v_def, c_ficha, 'g')) <> 1 then
      raise exception 'espejo_cliente_visible: la marca de comprador_ficha no aparece exactamente una vez; no se aplica nada';
    end if;
    v_def := regexp_replace(v_def, c_ficha, E'if not public._cliente_ficha_visible(p_id) then\n    return;\n  end if;');
    if position('clients c0' in v_def) > 0 then
      raise exception 'espejo_cliente_visible: comprador_ficha conserva la condicion vieja tras el parche; no se aplica nada';
    end if;
    execute v_def;
  end if;

  if (select count(*) from pg_proc p
       where p.oid in ('public.contrato_guarda(uuid,jsonb)'::regprocedure, 'public.comprador_ficha(uuid)'::regprocedure)
         and p.prosecdef and 'search_path=""' = any (p.proconfig)
         and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')) <> 2 then
    raise exception 'espejo_cliente_visible: contrato_guarda o comprador_ficha han perdido DEFINER, search_path o permisos; no se aplica nada';
  end if;
end $parche$;

-- ============================================================ 5. Tipo permitido TAMBIEN al editar
create or replace function public.contratos_tipo_permitido()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_rol    text;
  v_tipos  text[];
begin
  -- 14-oct-2026: el trigger salta tambien en UPDATE OF tipo, y contrato_guarda hace `set tipo = v_tipo` en CADA
  -- guardado: al editar solo se mira si el tipo CAMBIA. Asi el agente al que le quitan un tipo sigue pudiendo
  -- guardar los borradores que ya tenia de ese tipo (la fila que pierde sigue editable, patron LAW-51).
  if tg_op = 'UPDATE' then
    if new.tipo is not distinct from old.tipo then
      return new;
    end if;
  end if;

  -- Sin sesión (service role, edges, cron) no se comprueba: esos caminos ya
  -- tienen su propia puerta y bloquearlos aquí rompería la firma automática.
  if auth.uid() is null then
    return new;
  end if;

  select rol, tipos_contrato into v_rol, v_tipos
    from public.usuarios where user_id = auth.uid();

  -- Solo aplica a AGENTES: un administrador trabaja con todos los tipos por
  -- definición, y así además nadie puede dejarse a sí mismo sin poder emitir.
  if v_rol is distinct from 'agente' then
    return new;
  end if;

  if v_tipos is null or cardinality(v_tipos) = 0 then
    raise exception 'No tienes ningún tipo de contrato asignado. Pídelo a un administrador en Usuarios.'
      using errcode = '42501';
  end if;

  if not (new.tipo = any(v_tipos)) then
    raise exception 'No tienes permiso para emitir contratos de tipo "%". Pídeselo a un administrador en Usuarios.', new.tipo
      using errcode = '42501';
  end if;

  return new;
end;
$function$;
create or replace trigger trg_contratos_tipo_permitido before insert or update of tipo on public.contratos
  for each row execute function public.contratos_tipo_permitido();
-- funcion de trigger: nadie la llama a mano (hoy tenia EXECUTE para authenticated; se retira, no se abre nada)
revoke all on function public.contratos_tipo_permitido() from public, anon, authenticated;
