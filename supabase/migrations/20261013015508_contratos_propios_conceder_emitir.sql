-- Contratos propios: que se puedan CONCEDER a un agente y que el agente los pueda EMITIR (13-oct-2026, divergencia (2) de
-- suite_lawang.md). Dos partes:
--   A. trigger en `usuarios.tipos_contrato` (que se puede conceder);
--   B. el tipo propio y los campos `cx_` resuelven la empresa tambien cuando el contrato llega solo con el NOMBRE del proyecto.
--
-- ===================================================================================== A. que se puede conceder
--
-- Dueño del dato: `usuarios.tipos_contrato` (lo que un AGENTE puede emitir; contratos_tipo_permitido lo exige al
-- insertar un contrato). Lo escriben tres caminos y hasta hoy ninguno comprobaba que el valor existiera:
--   * usuario_guarda_permisos (pantalla Permisos): un super admin global o de empresa guardaba CUALQUIER texto, incluido
--     el slug del contrato propio de OTRA empresa (medido en su definicion: solo comprueba «lo que tienes tu» para los
--     que no son super).
--   * usuario_alta_empresa (alta por un rol de empresa, con la sesion de quien da el alta): igual para el super de empresa.
--   * la edge admin-usuarios (alta global y solicitudes de /partners/, con service_role): tiraba en silencio todo lo que
--     no fuera uno de los 17, asi que un contrato propio no se podia dar en el alta.
-- Este trigger es la unica puerta comun a los tres. Solo mira lo AÑADIDO (new menos old): lo que la persona ya tenia se
-- conserva aunque hoy no valga, para que guardar su ficha no le quite nada en silencio (medido el 13-oct: 0 valores
-- fuera de los 17 en toda la tabla, asi que hoy no hay nada que conservar).
--
-- Reglas de cada tipo añadido:
--   1. Es uno de los 17 o el slug de un contrato propio de una empresa. Se pregunta a `_plantilla_slug_de_tipo`, la MISMA
--      resolucion que usan los contratos (_trg_contrato_tipo_valido): una lista sola, no una tercera copia de los 17.
--   2. Si es propio y la persona tiene empresas marcadas, es de una de ellas. Si no, nunca podria emitirlo:
--      _trg_contrato_tipo_valido exige que el contrato propio sea de la empresa del proyecto, y sus proyectos son de sus
--      empresas (usuario_guarda_permisos).
--   3. Si es propio y hay sesion (Permisos, alta de empresa), la empresa del contrato esta en el alcance de quien lo
--      concede (`empresa_en_alcance`, la misma puerta que plantilla_contratos_propios_activos, que es de donde la pantalla
--      saca la lista). Sin sesion (edge con service_role, MCP) esta regla no aplica: la edge comprueba a quien llama.
-- No cambia quien puede conceder (eso sigue en usuario_guarda_permisos / usuario_alta_empresa / la edge): solo QUE se
-- puede conceder.
--
-- Prueba: supabase/pruebas/contrato_propio_permiso_agente.sql (en transaccion que acaba en raise).
-- Vuelta atras (A y B): supabase/reversion_tipos_contrato/vuelta_atras.sql (no toca datos).

create or replace function public._trg_usuarios_tipos_contrato_validos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_t   text;
  v_emp text;
begin
  for v_t in
    select x.t from unnest(coalesce(new.tipos_contrato, '{}'::text[])) as x(t)
    except
    select y.t from unnest(case when tg_op = 'UPDATE' then coalesce(old.tipos_contrato, '{}'::text[]) else '{}'::text[] end) as y(t)
  loop
    if v_t is null or public._plantilla_slug_de_tipo(v_t) is null then
      raise exception 'Tipo de contrato desconocido: %', coalesce(v_t, '(vacio)') using errcode = '22023';
    end if;
    v_emp := null;
    select p.empresa into v_emp from public.plantillas_contrato p where p.slug = v_t and p.empresa is not null;
    if v_emp is not null then
      if cardinality(coalesce(new.empresas, '{}'::text[])) > 0 and not (v_emp = any (new.empresas)) then
        raise exception 'El contrato propio % es de otra empresa que la de esa persona', v_t using errcode = '42501';
      end if;
      if (select auth.uid()) is not null and not public.empresa_en_alcance(v_emp) then
        raise exception 'No puedes conceder un contrato propio de una empresa que no es tuya: %', v_t using errcode = '42501';
      end if;
    end if;
  end loop;
  return new;
end
$f$;

-- Funcion de trigger: nadie la llama por RPC (nace cerrada, como _trg_contrato_tipo_valido).
revoke all on function public._trg_usuarios_tipos_contrato_validos() from public, anon, authenticated, service_role;

create trigger usuarios_tipos_contrato_validos
  before insert or update of tipos_contrato on public.usuarios
  for each row execute function public._trg_usuarios_tipos_contrato_validos();

-- ===================================================================================== B. que el agente lo pueda emitir
-- Medido el 13-oct con la prueba de arriba, como un agente real: `contrato_guarda` (lo unico por lo que guarda la pantalla,
-- contracts/app.html:5552) inserta el contrato con `proyecto_nombre` y SIN `proyecto_id`; el id lo pone despues el trigger
-- `trg_espejo_proyecto`. Pero los BEFORE se disparan por orden alfabetico y `trg_00_contrato_tipo_valido` y
-- `trg_contrato_campos_propios` van ANTES que `trg_espejo_proyecto`: ven `proyecto_id` nulo, no hay empresa, y rechazan.
-- Resultado: NINGUN contrato propio se podia guardar desde la pantalla («Tipo de contrato no valido para esta empresa»), y un
-- contrato nuevo con un campo `cx_` tampoco («Este contrato no tiene empresa»). La prueba E9 no lo vio porque insertaba con
-- `proyecto_id` puesto a mano, como postgres.
-- Arreglo: el proyecto se resuelve con UNA funcion (`_contrato_proyecto_de`), la misma regla que ya aplicaba el espejo (el id si
-- viene; si no, el proyecto con ese nombre), y la usan el espejo y los dos triggers. No se renombran triggers: cambiar el orden
-- de `trg_espejo_proyecto` haria que otros ~8 triggers vieran el proyecto donde hoy no lo ven, y eso es otra revision.
create or replace function public._contrato_proyecto_de(p_id uuid, p_nombre text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $f$
  select coalesce(p_id,
                  (select p.id from public.proyectos p
                    where nullif(btrim(coalesce(p_nombre, '')), '') is not null and p.nombre = p_nombre
                    limit 1))
$f$;
revoke all on function public._contrato_proyecto_de(uuid, text) from public, anon, authenticated, service_role;

create or replace function public.trg_espejo_proyecto()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_nombre text;
begin
  -- la regla del proyecto vive en _contrato_proyecto_de (13-oct-2026): la usan tambien _trg_contrato_tipo_valido y
  -- _trg_contrato_campos_propios, que se disparan antes que este trigger
  new.proyecto_id := public._contrato_proyecto_de(new.proyecto_id, new.proyecto_nombre);

  if new.proyecto_id is not null then
    select p.nombre into v_nombre from public.proyectos p where p.id = new.proyecto_id;
    if v_nombre is not null then
      new.proyecto_nombre := v_nombre;
    end if;
  end if;
  return new;
end
$function$;

create or replace function public._trg_contrato_tipo_valido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_emp text;
begin
  if new.tipo = any (array['reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer', 'carta_reserva', 'carta_reserva_ampliada', 'acuerdo_comercial', 'protocolo_operativo',
                           'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa', 'poa', 'cc00014_timon', 'carta_reserva_pma', 'adenda', 'carta_reserva_investor_deck']::text[]) then
    return new;
  end if;
  -- 13-oct-2026: el proyecto tambien por su nombre (contrato_guarda no trae proyecto_id; lo pone trg_espejo_proyecto, que va despues)
  v_emp := public.empresa_de_proyecto(public._contrato_proyecto_de(new.proyecto_id, new.proyecto_nombre));
  if v_emp is null or not exists (select 1 from public.plantillas_contrato t where t.slug = new.tipo and t.empresa = v_emp) then
    raise exception 'Tipo de contrato no valido para esta empresa: %', new.tipo using errcode = '23514';
  end if;
  return new;
end $function$;

-- _trg_contrato_campos_propios: parche de UNA linea sobre la funcion viva (es larga y solo cambia como saca la empresa).
-- Marca exacta medida el 13-oct (aparece una vez, sin CR); si no aparece, para y no toca nada.
do $parche$
declare
  d text := pg_get_functiondef('public._trg_contrato_campos_propios'::regproc);
  marca text := 'emp := case when new.proyecto_id is null then null else public.empresa_de_proyecto(new.proyecto_id) end;';
  nuevo text := 'emp := public.empresa_de_proyecto(public._contrato_proyecto_de(new.proyecto_id, new.proyecto_nombre));   -- 13-oct-2026: tambien por el nombre del proyecto (contrato_guarda)';
begin
  if (length(d) - length(replace(d, marca, ''))) / length(marca) <> 1 then
    raise exception '_trg_contrato_campos_propios: la marca no aparece exactamente una vez; no se parchea' using errcode = 'P0001';
  end if;
  execute replace(d, marca, nuevo);
end
$parche$;
