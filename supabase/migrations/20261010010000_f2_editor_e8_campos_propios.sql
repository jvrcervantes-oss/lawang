-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «editor de textos de contrato» (encargos/20261008_lawang_editor_textos_contrato.md) · E8 · CATALOGO DE CAMPOS PROPIOS POR EMPRESA (8-oct-2026).
-- DECISION DEL OWNER (8-oct): cada empresa define sus propios campos ({{cx_algo}}) sin llamar al estudio; el VALOR va en el JSON de datos del contrato (datos.fields.cx_algo),
--   sin tablas ni migracion por contrato; maxima libertad del cliente, tambien para contratos nuevos. Revision previa (#225): Datos, Seguridad, Bots, hallazgos plegados en el encargo.
-- QUE HACE:
--   1. Tabla `plantilla_campos_propios` (empresa, clave cx_[a-z0-9_]{1,40}, etiqueta es/en/id, tipo cerrado texto|numero|fecha|importe|lista|si_no, opciones, obligatorio, sensible
--      [por defecto SI], archivado). Sin GRANT directo a nadie: todo por RPC. Clave, empresa y autor son inmutables; el TIPO (y quitar opciones) es inmutable en cuanto una version o un
--      contrato usa el campo (trigger, no solo RPC). Un campo en uso se ARCHIVA, no se borra; borrar = solo si ninguna version referencia el marcador ni ningun contrato guarda valor
--      (trigger BEFORE DELETE + bloqueo de fila: el validador toma FOR SHARE sobre el catalogo al guardar y el borrado toma FOR UPDATE).
--   2. VALIDADOR DE MARCADORES: `_plantilla_texto` acepta {{cx_x}} SOLO si x esta en el catalogo de ESA empresa y no esta archivado en el momento de guardar (lookup en servidor, por un
--      ajuste local a la transaccion `lw.cx_catalogo` que fijan _plantilla_exige_valido y plantilla_contrato_revisa y que se vacia al acabar). Sin empresa en contexto (semilla, llamada
--      directa) todo cx_ se rechaza: lo nuevo nace cerrado. Un cx_ no es «bloque fijo» ni entra en <!--if:--> ni en data-campo (siguen cerrados). El ESQUELETO se analiza en modo abierto
--      (`lw.cx_abierto`) para que archivar un campo ya activo en el texto estandar no rompa la validacion de todo borrador nuevo.
--   3. VALORES: `_cx_valor(tipo, opciones, valor)` es la unica verdad (texto <=200, sin control/bidi/ancho cero [se eliminan], sin < > { }; numero/importe por el parser unico lw_importe y
--      se guardan en forma canonica; fecha ISO real 1900-2200; lista dentro de opciones; si_no 'si'|'no'). Se aplica en dos sitios: la RPC `plantilla_campo_propio_valida` (la usa el formulario) y
--      un TRIGGER en `contratos` (BEFORE INSERT OR UPDATE OF datos) que revisa SOLO las claves cx_ que cambian: una clave sin catalogo en la empresa del proyecto, de otra empresa, archivada
--      o con valor invalido hace fallar el guardado. Un contrato sin claves cx_ (todos los de hoy) sale por el camino rapido sin tocar nada. El navegador no manda: el servidor decide.
--   4. EXPOSICION al bot/IA: `plantilla_campos_cx_publicos(empresa | contrato)` lista los cx_ NO sensibles; bot-agentes (edge) excluye los sensibles y los cx_ fuera de catalogo.
--   5. INSERCION SEGURA del valor en el documento: ya la hace contracts/app.html buildDoc (una sola pasada con funcion de reemplazo + esc() de & < > "), asi que `{{otro}}` dentro de un valor
--      no se vuelve a expandir; aqui ademas el servidor no deja entrar < > { } en el valor. Lo fija contracts/campos_propios_insercion.test.js.
-- RPC (todas SECURITY DEFINER, search_path vacio, nacen cerradas y se abren solo a `authenticated`; empresa_en_alcance + rol dentro):
--   plantilla_campo_propio_lista (agente en alcance) · _guarda / _archiva / _borra (admin de la empresa) · plantilla_campo_propio_valida (agente en alcance) · plantilla_campos_cx_publicos (agente).
-- Llamadores con nombre: la pantalla `intranet/v4/textos-contrato/` (catalogo y pastillas), el formulario de contracts/app.html (valida) y la edge bot-agentes (publicos). Hasta que se conecten no las llama nadie.
-- destructivo-ok: solo CREA (1 tabla, 4 triggers, funciones nuevas) y reemplaza 4 funciones del validador por la misma con una rama anadida; no toca ninguna fila existente
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_editor_e8_campos_propios.sql

-- ------------------------------------------------------------------------------------------------------------------ ayudantes puros
create function public._cx_opciones_ok(p jsonb) returns boolean language sql immutable set search_path = '' as $$
  select p is not null and jsonb_typeof(p) = 'array' and jsonb_array_length(p) between 1 and 50
     and not exists (select 1 from jsonb_array_elements(p) e
                      where jsonb_typeof(e) <> 'string'
                         or length(btrim(e #>> '{}')) not between 1 and 80
                         or (e #>> '{}') <> btrim(e #>> '{}')
                         or (e #>> '{}') ~ '[<>{}\x01-\x1f\x7f‪-‮⁦-⁩‎‏؜﻿  ​-‍⁠­᠎]')
$$;

-- el valor de un campo: {ok, v (forma canonica), err}. Unica verdad de la validacion por tipo.
create function public._cx_valor(p_tipo text, p_opciones jsonb, p_valor jsonb) returns jsonb language plpgsql stable set search_path = '' as $$
declare t text; n numeric; d date;
begin
  if p_valor is null or jsonb_typeof(p_valor) = 'null' then return jsonb_build_object('ok', true, 'v', ''); end if;
  if jsonb_typeof(p_valor) not in ('string', 'number') then
    return jsonb_build_object('ok', false, 'err', 'el valor debe ser un texto o un numero');
  end if;
  t := p_valor #>> '{}';
  -- se ELIMINAN control, bidireccionales (Trojan Source) y ancho cero; tabuladores y saltos pasan a espacio
  t := pg_catalog.regexp_replace(t, '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f‪-‮⁦-⁩‎‏؜﻿  ​-‍⁠­᠎]', '', 'g');
  t := btrim(pg_catalog.regexp_replace(t, '[\t\r\n ]+', ' ', 'g'));
  if t = '' then return jsonb_build_object('ok', true, 'v', ''); end if;
  if pg_catalog.length(t) > 200 then return jsonb_build_object('ok', false, 'err', 'mas de 200 caracteres'); end if;
  if t ~ '[<>{}]' then return jsonb_build_object('ok', false, 'err', 'no admite los signos < > { }'); end if;
  if p_tipo = 'texto' then
    return jsonb_build_object('ok', true, 'v', t);
  elsif p_tipo in ('numero', 'importe') then
    t := pg_catalog.replace(t, ' ', '');
    if t !~ '^-?[0-9][0-9.,]*$' then return jsonb_build_object('ok', false, 'err', 'no es un numero (solo cifras, punto y coma)'); end if;
    n := public.lw_importe(t);                                               -- el parser unico del estudio (reference_dos_parsers_para_el_mismo_importe)
    if n is null then return jsonb_build_object('ok', false, 'err', 'no es un numero'); end if;
    if abs(n) >= 1000000000000000 then return jsonb_build_object('ok', false, 'err', 'numero demasiado grande'); end if;
    if p_tipo = 'importe' then
      if n < 0 then return jsonb_build_object('ok', false, 'err', 'un importe no es negativo'); end if;
      if n <> round(n, 2) then return jsonb_build_object('ok', false, 'err', 'un importe lleva como mucho 2 decimales'); end if;
    end if;
    return jsonb_build_object('ok', true, 'v', pg_catalog.trim_scale(n)::text);   -- canonico: «120.000» y «120000» guardan lo mismo, y ::numeric ya no discrepa
  elsif p_tipo = 'fecha' then
    if t !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return jsonb_build_object('ok', false, 'err', 'la fecha va como AAAA-MM-DD'); end if;
    begin d := t::date; exception when others then return jsonb_build_object('ok', false, 'err', 'fecha que no existe'); end;
    if pg_catalog.to_char(d, 'YYYY-MM-DD') <> t or d < date '1900-01-01' or d > date '2200-12-31' then
      return jsonb_build_object('ok', false, 'err', 'fecha fuera de rango (1900-2200) o que no existe');
    end if;
    return jsonb_build_object('ok', true, 'v', t);
  elsif p_tipo = 'lista' then
    if p_opciones is null or not (p_opciones ? t) then return jsonb_build_object('ok', false, 'err', 'no es una de las opciones del campo'); end if;
    return jsonb_build_object('ok', true, 'v', t);
  elsif p_tipo = 'si_no' then
    if t not in ('si', 'no') then return jsonb_build_object('ok', false, 'err', 'solo «si» o «no»'); end if;
    return jsonb_build_object('ok', true, 'v', t);
  end if;
  return jsonb_build_object('ok', false, 'err', 'tipo de campo desconocido');
end $$;
revoke all on function public._cx_opciones_ok(jsonb), public._cx_valor(text, jsonb, jsonb) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------------------------ tabla
create table public.plantilla_campos_propios (
  id             uuid        primary key default gen_random_uuid(),
  empresa        text        not null references public.empresas (clave),
  clave          text        not null,
  etiqueta_es    text        not null,
  etiqueta_en    text,
  etiqueta_id    text,
  tipo           text        not null,
  opciones       jsonb,
  obligatorio    boolean     not null default false,
  sensible       boolean     not null default true,
  archivado      boolean     not null default false,
  archivado_por  text,
  archivado_en   timestamptz,
  autor          text        not null check (btrim(autor) <> ''),
  creado_en      timestamptz not null default now(),
  actualizado_por text,
  actualizado_en timestamptz,
  unique (empresa, clave),
  constraint campo_propio_clave    check (clave ~ '^cx_[a-z0-9_]{1,40}$'),
  constraint campo_propio_tipo     check (tipo in ('texto', 'numero', 'fecha', 'importe', 'lista', 'si_no')),
  constraint campo_propio_opciones check ((tipo = 'lista') = (opciones is not null) and (opciones is null or public._cx_opciones_ok(opciones))),
  constraint campo_propio_etiquetas check (
        length(btrim(etiqueta_es)) between 1 and 80 and etiqueta_es !~ '[<>{}\x01-\x1f\x7f]'
    and (etiqueta_en is null or (length(btrim(etiqueta_en)) between 1 and 80 and etiqueta_en !~ '[<>{}\x01-\x1f\x7f]'))
    and (etiqueta_id is null or (length(btrim(etiqueta_id)) between 1 and 80 and etiqueta_id !~ '[<>{}\x01-\x1f\x7f]'))),
  constraint campo_propio_archivado_firmado check (not archivado or (archivado_por is not null and archivado_en is not null))
);
comment on table public.plantilla_campos_propios is
  'Catalogo de campos propios ({{cx_*}}) de cada empresa para sus textos de contrato (owner 8-oct-2026, E8). El VALOR vive en contratos.datos.fields.cx_*, no aqui. Sin GRANT: se lee y se escribe por RPC (plantilla_campo_propio_*). sensible=true (por defecto) = el bot y la IA no lo ven. Un campo en uso se archiva, no se borra.';
alter table public.plantilla_campos_propios enable row level security;
revoke all on table public.plantilla_campos_propios from public, anon, authenticated, service_role;

-- ¿lo usa alguna version (aunque este borrada o retirada) o algun contrato con valor? Se consulta SOLO al tocar tipo/borrado: es una lectura de cuerpos de una sola empresa
create function public._cx_en_uso(p_empresa text, p_clave text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare nv int; nc int;
begin
  select count(*) into nv from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.empresa = p_empresa and pg_catalog.strpos(c.cuerpo_html, '{{' || p_clave || '}}') > 0;
  select count(*) into nc from public.contratos k join public.proyectos p on p.id = k.proyecto_id
   where p.empresa = p_empresa and k.datos_fields ? p_clave and coalesce(k.datos_fields ->> p_clave, '') <> '';
  return jsonb_build_object('versiones', nv, 'contratos', nc);
end $$;
revoke all on function public._cx_en_uso(text, text) from public, anon, authenticated, service_role;

create function public._trg_cx_campo_ins() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.clave = any (public._plantilla_campos_if()) then
    raise exception 'La clave % choca con un campo del sistema', new.clave using errcode = '22023';
  end if;
  if (select count(*) from public.plantilla_campos_propios x where x.empresa = new.empresa) >= 200 then
    raise exception 'Una empresa puede tener como mucho 200 campos propios' using errcode = '54000';
  end if;
  if new.archivado or new.archivado_por is not null or new.archivado_en is not null then
    raise exception 'Un campo propio nace sin archivar' using errcode = '55000';
  end if;
  return new;
end $$;
create function public._trg_cx_campo_upd() returns trigger language plpgsql security definer set search_path = '' as $$
declare u jsonb; n int;
begin
  if (new.id, new.empresa, new.clave, new.autor, new.creado_en) is distinct from (old.id, old.empresa, old.clave, old.autor, old.creado_en) then
    raise exception 'La clave, la empresa y el autor de un campo propio no cambian' using errcode = '55000';
  end if;
  if new.tipo <> old.tipo or new.opciones is distinct from old.opciones then
    u := public._cx_en_uso(old.empresa, old.clave);
    n := (u ->> 'versiones')::int + (u ->> 'contratos')::int;
    if n > 0 then
      if new.tipo <> old.tipo then
        raise exception 'El tipo de % no cambia: lo usan % version(es) y % contrato(s). Archivalo y crea otro campo.', old.clave, u ->> 'versiones', u ->> 'contratos' using errcode = '55000';
      end if;
      if new.opciones is null or not (new.opciones @> old.opciones) then
        raise exception 'En % solo se pueden anadir opciones: ya lo usan % version(es) y % contrato(s)', old.clave, u ->> 'versiones', u ->> 'contratos' using errcode = '55000';
      end if;
    end if;
  end if;
  return new;
end $$;
create function public._trg_cx_campo_del() returns trigger language plpgsql security definer set search_path = '' as $$
declare u jsonb; n int;
begin
  u := public._cx_en_uso(old.empresa, old.clave);
  n := (u ->> 'versiones')::int + (u ->> 'contratos')::int;
  if n > 0 then
    raise exception 'No se borra % : lo usan % version(es) y % contrato(s). Archivalo para que no se ofrezca mas.', old.clave, u ->> 'versiones', u ->> 'contratos' using errcode = '55000';
  end if;
  return old;
end $$;
revoke all on function public._trg_cx_campo_ins(), public._trg_cx_campo_upd(), public._trg_cx_campo_del() from public, anon, authenticated, service_role;
create trigger trg_cx_campo_ins before insert on public.plantilla_campos_propios for each row execute function public._trg_cx_campo_ins();
create trigger trg_cx_campo_upd before update on public.plantilla_campos_propios for each row execute function public._trg_cx_campo_upd();
create trigger trg_cx_campo_del before delete on public.plantilla_campos_propios for each row execute function public._trg_cx_campo_del();

-- ------------------------------------------------------------------------------------------------------------------ autorizacion comun (devuelve el email de quien actua)
create function public._cx_autoriza(p_empresa text, p_escribe boolean) returns text language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null then raise exception 'Falta la empresa' using errcode = '22023'; end if;
  if p_escribe then
    if not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
      raise exception 'Los campos propios de una empresa los escribe su administracion' using errcode = '42501';
    end if;
  else
    if not (public.es_agente() and public.empresa_en_alcance(p_empresa)) then
      raise exception 'Esa empresa no es de tu alcance' using errcode = '42501';
    end if;
  end if;
  return coalesce((select auth.email()), (select auth.uid())::text);
end $$;
revoke all on function public._cx_autoriza(text, boolean) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------------------------ RPC de escritura
create function public.plantilla_campo_propio_guarda(p_empresa text, p_clave text, p_etiqueta_es text, p_etiqueta_en text, p_etiqueta_id text,
                                                    p_tipo text, p_opciones jsonb, p_obligatorio boolean, p_sensible boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_email text; c public.plantilla_campos_propios%rowtype; v_nuevo boolean;
begin
  v_email := public._cx_autoriza(p_empresa, true);
  if p_clave is null or p_clave !~ '^cx_[a-z0-9_]{1,40}$' then
    raise exception 'La clave de un campo propio empieza por cx_ y sigue con hasta 40 letras minusculas, cifras o guion bajo' using errcode = '22023';
  end if;
  if p_tipo is null or p_tipo not in ('texto', 'numero', 'fecha', 'importe', 'lista', 'si_no') then
    raise exception 'Tipo de campo no valido (texto, numero, fecha, importe, lista o si_no)' using errcode = '22023';
  end if;
  if p_tipo = 'lista' and not public._cx_opciones_ok(p_opciones) then
    raise exception 'Una lista lleva de 1 a 50 opciones de texto (1-80 caracteres, sin < > { })' using errcode = '22023';
  end if;
  if p_tipo <> 'lista' and p_opciones is not null and p_opciones <> 'null'::jsonb then
    raise exception 'Solo una lista lleva opciones' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cx/' || p_empresa, 0));
  select * into c from public.plantilla_campos_propios where empresa = p_empresa and clave = p_clave for update;
  v_nuevo := not found;
  if v_nuevo then
    insert into public.plantilla_campos_propios (empresa, clave, etiqueta_es, etiqueta_en, etiqueta_id, tipo, opciones, obligatorio, sensible, autor)
    values (p_empresa, p_clave, btrim(p_etiqueta_es), nullif(btrim(p_etiqueta_en), ''), nullif(btrim(p_etiqueta_id), ''), p_tipo,
            case when p_tipo = 'lista' then p_opciones end, coalesce(p_obligatorio, false), coalesce(p_sensible, true), v_email)
    returning * into c;
  else
    update public.plantilla_campos_propios
       set etiqueta_es = btrim(p_etiqueta_es), etiqueta_en = nullif(btrim(p_etiqueta_en), ''), etiqueta_id = nullif(btrim(p_etiqueta_id), ''),
           tipo = p_tipo, opciones = case when p_tipo = 'lista' then p_opciones end, obligatorio = coalesce(p_obligatorio, false), sensible = coalesce(p_sensible, true),
           actualizado_por = v_email, actualizado_en = now()
     where id = c.id returning * into c;
  end if;
  return jsonb_build_object('clave', c.clave, 'nuevo', v_nuevo, 'tipo', c.tipo, 'sensible', c.sensible, 'archivado', c.archivado);
end $$;

create function public.plantilla_campo_propio_archiva(p_empresa text, p_clave text, p_archivado boolean default true) returns void
language plpgsql security definer set search_path = '' as $$
declare v_email text; c public.plantilla_campos_propios%rowtype;
begin
  v_email := public._cx_autoriza(p_empresa, true);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cx/' || p_empresa, 0));
  select * into c from public.plantilla_campos_propios where empresa = p_empresa and clave = p_clave for update;
  if not found then raise exception 'Ese campo propio no existe' using errcode = '22023'; end if;
  if c.archivado is not distinct from coalesce(p_archivado, true) then return; end if;
  update public.plantilla_campos_propios
     set archivado = coalesce(p_archivado, true),
         archivado_por = case when coalesce(p_archivado, true) then v_email end, archivado_en = case when coalesce(p_archivado, true) then now() end,
         actualizado_por = v_email, actualizado_en = now()
   where id = c.id;
end $$;

create function public.plantilla_campo_propio_borra(p_empresa text, p_clave text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  perform public._cx_autoriza(p_empresa, true);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cx/' || p_empresa, 0));
  -- FOR UPDATE: un guardado de texto que lo referencie tiene FOR SHARE sobre esta fila hasta que su transaccion acaba; aqui se espera y el trigger cuenta con la foto nueva
  select id into v_id from public.plantilla_campos_propios where empresa = p_empresa and clave = p_clave for update;
  if v_id is null then raise exception 'Ese campo propio no existe' using errcode = '22023'; end if;
  delete from public.plantilla_campos_propios where id = v_id;                     -- el trigger BEFORE DELETE niega si hay version o contrato que lo use
end $$;

-- ------------------------------------------------------------------------------------------------------------------ RPC de lectura y validacion
create function public.plantilla_campo_propio_lista(p_empresa text, p_con_uso boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform public._cx_autoriza(p_empresa, false);
  if coalesce(p_con_uso, false) and not public.es_admin_de(p_empresa) then
    raise exception 'El uso de cada campo lo ve la administracion de la empresa' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(
           jsonb_build_object('clave', c.clave, 'etiqueta', jsonb_build_object('es', c.etiqueta_es, 'en', c.etiqueta_en, 'id', c.etiqueta_id),
                              'tipo', c.tipo, 'opciones', c.opciones, 'obligatorio', c.obligatorio, 'sensible', c.sensible,
                              'archivado', c.archivado, 'creado_en', c.creado_en)
           || case when coalesce(p_con_uso, false)
                   then jsonb_build_object('uso', jsonb_build_object('versiones', coalesce(uv.n, 0), 'contratos', coalesce(uc.n, 0))) else '{}'::jsonb end
           order by c.clave), '[]'::jsonb)
    into r
    from public.plantilla_campos_propios c
    left join (select m[1] as k, count(distinct v.id) as n
                 from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos co on co.version_id = v.id,
                      pg_catalog.regexp_matches(co.cuerpo_html, '\{\{(cx_[a-z0-9_]{1,40})\}\}', 'g') m
                where coalesce(p_con_uso, false) and v.empresa = p_empresa group by 1) uv on uv.k = c.clave
    left join (select kk as k, count(*) as n
                 from public.contratos ct join public.proyectos p on p.id = ct.proyecto_id, jsonb_object_keys(ct.datos_fields) kk
                where coalesce(p_con_uso, false) and p.empresa = p_empresa and kk like 'cx\_%' and coalesce(ct.datos_fields ->> kk, '') <> '' group by kk) uc on uc.k = c.clave
   where c.empresa = p_empresa;
  return r;
end $$;

-- valida (sin guardar) un lote de valores: lo que respondera el trigger de contratos al guardarlos. Devuelve los valores en forma canonica.
create function public.plantilla_campo_propio_valida(p_empresa text, p_valores jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare k text; v jsonb; c public.plantilla_campos_propios%rowtype; r jsonb; errs jsonb := '{}'::jsonb; vals jsonb := '{}'::jsonb; vacios text[] := '{}';
begin
  perform public._cx_autoriza(p_empresa, false);
  if p_valores is null or jsonb_typeof(p_valores) <> 'object' then raise exception 'Los valores van como un objeto {clave: valor}' using errcode = '22023'; end if;
  if (select count(*) from jsonb_object_keys(p_valores)) > 200 then raise exception 'Demasiados valores (200 como mucho)' using errcode = '22023'; end if;
  for k, v in select * from jsonb_each(p_valores) loop
    if k !~ '^cx_[a-z0-9_]{1,40}$' then
      errs := errs || jsonb_build_object(left(k, 60), 'no es una clave de campo propio');
      continue;
    end if;
    select * into c from public.plantilla_campos_propios x where x.empresa = p_empresa and x.clave = k;
    if not found then errs := errs || jsonb_build_object(k, 'no esta en el catalogo de esta empresa');
    elsif c.archivado then errs := errs || jsonb_build_object(k, 'campo archivado: ya no admite valores nuevos');
    else
      r := public._cx_valor(c.tipo, c.opciones, v);
      if (r ->> 'ok')::boolean then
        vals := vals || jsonb_build_object(k, r ->> 'v');
        if (r ->> 'v') = '' and c.obligatorio then vacios := vacios || k; end if;
      else
        errs := errs || jsonb_build_object(k, r ->> 'err');
      end if;
    end if;
  end loop;
  return jsonb_build_object('ok', errs = '{}'::jsonb, 'errores', errs, 'valores', vals, 'vacios_obligatorios', to_jsonb(vacios));
end $$;

-- los cx_ que el bot y la IA PUEDEN ver (no sensibles), por empresa o por contrato. Archivados incluidos: su valor sigue en los contratos viejos.
create function public.plantilla_campos_cx_publicos(p_empresa text default null, p_contrato uuid default null) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare v_emp text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if (p_empresa is null) = (p_contrato is null) then raise exception 'Se pide la empresa o el contrato, uno solo' using errcode = '22023'; end if;
  if p_contrato is not null then
    select p.empresa into v_emp from public.contratos c join public.proyectos p on p.id = c.proyecto_id where c.id = p_contrato;
    if v_emp is null or not (public.es_agente() and public.empresa_en_alcance(v_emp)) then return '{}'::text[]; end if;   -- cerrado por defecto: sin empresa o fuera de alcance, ninguno
  else
    v_emp := p_empresa;
    perform public._cx_autoriza(v_emp, false);
  end if;
  return coalesce(array(select clave from public.plantilla_campos_propios where empresa = v_emp and not sensible order by clave), '{}'::text[]);
end $$;

-- ------------------------------------------------------------------------------------------------------------------ contexto del validador (lookup en servidor)
create function public._plantilla_cx_contexto(p_empresa text, p_bloquea boolean) returns void language plpgsql volatile security definer set search_path = '' as $$
declare v text;
begin
  if p_bloquea then
    -- al GUARDAR: FOR SHARE sobre los campos vivos, para que un borrado concurrente espere a que este guardado confirme
    perform 1 from public.plantilla_campos_propios where empresa = p_empresa and not archivado for share;
  end if;
  select coalesce(string_agg(clave, ',' order by clave), '') into v from public.plantilla_campos_propios where empresa = p_empresa and not archivado;
  perform pg_catalog.set_config('lw.cx_catalogo', v, true);
  perform pg_catalog.set_config('lw.cx_abierto', '', true);                         -- el cuerpo nunca se analiza en modo abierto, venga lo que venga de fuera
end $$;
revoke all on function public._plantilla_cx_contexto(text, boolean) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------------------------ parche de las funciones del validador (misma tecnica que S3 en 20261008990100: una sola entrada, con asercion)
do $p$
declare d text; d2 text;
begin
  -- 1. _plantilla_texto: la rama cx_
  d := pg_get_functiondef('public._plantilla_texto(text,boolean)'::regprocedure);
  if d not like '%lw.cx_catalogo%' then
    d2 := replace(d, 'elsif not (mk = any (public._plantilla_marcadores())) then',
$r$elsif mk ~ '^cx_' then
          if mk !~ '^cx_[a-z0-9_]{1,40}$' then
            e := e || ('campo propio con forma no permitida {{' || left(mk, 40) || '}} (cx_ y hasta 40 letras minusculas, cifras o guion bajo)');
          elsif coalesce(pg_catalog.current_setting('lw.cx_abierto', true), '') <> '1'
                and not (mk = any (pg_catalog.string_to_array(coalesce(pg_catalog.current_setting('lw.cx_catalogo', true), ''), ','))) then
            e := e || ('campo propio {{' || mk || '}} no esta en el catalogo de campos de esta empresa, o esta archivado');
          end if;
        elsif not (mk = any (public._plantilla_marcadores())) then$r$);
    if d2 = d then raise exception 'parche E8: no encuentro la rama de marcadores desconocidos en _plantilla_texto'; end if;
    execute d2;
  end if;
  -- 2. _plantilla_valida: el esqueleto se analiza en modo abierto
  d := pg_get_functiondef('public._plantilla_valida(text,text,boolean)'::regprocedure);
  if d not like '%lw.cx_abierto%' then
    d2 := replace(d, 'b := public._plantilla_analiza(p_esqueleto, true);',
$r$perform pg_catalog.set_config('lw.cx_abierto', '1', true);
    b := public._plantilla_analiza(p_esqueleto, true);
    perform pg_catalog.set_config('lw.cx_abierto', '', true);$r$);
    if d2 = d then raise exception 'parche E8: no encuentro el analisis del esqueleto en _plantilla_valida'; end if;
    execute d2;
  end if;
  -- 3. plantilla_contrato_revisa (ensayo sin guardar): fija el catalogo de la empresa, sin bloqueo
  d := pg_get_functiondef('public.plantilla_contrato_revisa(text,text,text)'::regprocedure);
  if d not like '%_plantilla_cx_contexto%' then
    d2 := replace(d, 'r := public._plantilla_valida(p_cuerpo, v_esq, false);',
$r$perform public._plantilla_cx_contexto(p_empresa, false);
  r := public._plantilla_valida(p_cuerpo, v_esq, false);
  perform pg_catalog.set_config('lw.cx_catalogo', '', true);$r$);
    if d2 = d then raise exception 'parche E8: no encuentro la llamada al validador en plantilla_contrato_revisa'; end if;
    execute d2;
  end if;
end $p$;
-- el validador lee un ajuste de la transaccion: ya no es inmutable (un planificador podria cachear su resultado entre dos catalogos)
alter function public._plantilla_texto(text, boolean) stable;
alter function public._plantilla_analiza(text, boolean) stable;
alter function public._plantilla_valida(text, text, boolean) stable;
alter function public.plantilla_cuerpo_valida(text, text) stable;
alter function public.plantilla_cuerpo_valida_semilla(text, text) stable;
-- las tres que llaman a set_config no pueden ir en paralelo (parallel safe + set_config = riesgo de que el ajuste no llegue al trabajador)
alter function public._plantilla_valida(text, text, boolean) parallel unsafe;
alter function public.plantilla_cuerpo_valida(text, text) parallel unsafe;
alter function public.plantilla_cuerpo_valida_semilla(text, text) parallel unsafe;

-- 4. _plantilla_exige_valido: el camino de guardar, activar, restaurar y copiar fija el catalogo de la empresa (con bloqueo) y lo vacia al acabar
create or replace function public._plantilla_exige_valido(p_cuerpo text, p_empresa text, p_slug text) returns void
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if pg_catalog.to_regprocedure('public.plantilla_cuerpo_valida(text,text)') is null then
    raise exception 'El validador de plantillas no esta instalado: no se guarda ni se activa nada' using errcode = '55000';
  end if;
  perform public._plantilla_cx_contexto(p_empresa, true);
  execute 'select public.plantilla_cuerpo_valida($1, $2)' into r using p_cuerpo, public._plantilla_esqueleto(p_empresa, p_slug);
  perform pg_catalog.set_config('lw.cx_catalogo', '', true);
  if r is null or coalesce((r ->> 'ok')::boolean, false) is not true then
    raise exception 'El texto no pasa la validacion: %', coalesce(left((select string_agg(e, ' | ') from (select jsonb_array_elements_text(r -> 'errores') e limit 5) q), 600), 'sin detalle') using errcode = '22023';
  end if;
end $$;
revoke all on function public._plantilla_exige_valido(text, text, text) from public, anon, authenticated, service_role;
revoke all on function public._plantilla_texto(text, boolean), public._plantilla_analiza(text, boolean), public._plantilla_valida(text, text, boolean),
  public.plantilla_cuerpo_valida(text, text), public.plantilla_cuerpo_valida_semilla(text, text) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------------------------ el punto de validacion de los VALORES en contratos
create function public._trg_contrato_campos_propios() returns trigger language plpgsql security definer set search_path = '' as $$
declare f jsonb := new.datos -> 'fields'; of_ jsonb; k text; v jsonb; c public.plantilla_campos_propios%rowtype; r jsonb; emp text; sale jsonb := null;
begin
  if f is null or jsonb_typeof(f) <> 'object' then return new; end if;
  if not exists (select 1 from jsonb_object_keys(f) kk where kk like 'cx\_%') then return new; end if;     -- camino rapido: todos los contratos de hoy
  if tg_op = 'UPDATE' then of_ := old.datos -> 'fields'; end if;
  emp := case when new.proyecto_id is null then null else public.empresa_de_proyecto(new.proyecto_id) end;
  for k in select kk from jsonb_object_keys(f) kk where kk like 'cx\_%' loop
    v := f -> k;
    if of_ is not null and jsonb_typeof(of_) = 'object' and (of_ -> k) is not distinct from v then continue; end if;      -- sin cambio: un valor viejo nunca bloquea otro guardado
    if v is null or jsonb_typeof(v) = 'null' or v = '""'::jsonb then continue; end if;                                       -- vaciar siempre se puede
    if k !~ '^cx_[a-z0-9_]{1,40}$' then raise exception 'Campo propio con forma no permitida: %', left(k, 60) using errcode = '22023'; end if;
    if emp is null then raise exception 'Este contrato no tiene empresa: no admite campos propios (%)', k using errcode = '22023'; end if;
    select * into c from public.plantilla_campos_propios x where x.empresa = emp and x.clave = k;
    if not found then raise exception 'El campo % no esta en el catalogo de campos de esta empresa', k using errcode = '22023'; end if;
    if c.archivado then raise exception 'El campo % esta archivado: ya no admite valores nuevos', k using errcode = '22023'; end if;
    r := public._cx_valor(c.tipo, c.opciones, v);
    if not (r ->> 'ok')::boolean then raise exception 'Valor no valido en %: %', k, r ->> 'err' using errcode = '22023'; end if;
    if to_jsonb(r ->> 'v') is distinct from v then sale := jsonb_set(coalesce(sale, new.datos), array['fields', k], to_jsonb(r ->> 'v')); end if;   -- forma canonica
  end loop;
  if sale is not null then new.datos := sale; end if;
  return new;
end $$;
revoke all on function public._trg_contrato_campos_propios() from public, anon, authenticated, service_role;
create trigger trg_contrato_campos_propios before insert or update of datos on public.contratos for each row execute function public._trg_contrato_campos_propios();

-- ------------------------------------------------------------------------------------------------------------------ permisos: las RPC nacen cerradas y se abren solo a authenticated
revoke all on function public.plantilla_campo_propio_guarda(text, text, text, text, text, text, jsonb, boolean, boolean),
                       public.plantilla_campo_propio_archiva(text, text, boolean),
                       public.plantilla_campo_propio_borra(text, text),
                       public.plantilla_campo_propio_lista(text, boolean),
                       public.plantilla_campo_propio_valida(text, jsonb),
                       public.plantilla_campos_cx_publicos(text, uuid) from public, anon, service_role;
grant execute on function public.plantilla_campo_propio_guarda(text, text, text, text, text, text, jsonb, boolean, boolean),
                          public.plantilla_campo_propio_archiva(text, text, boolean),
                          public.plantilla_campo_propio_borra(text, text),
                          public.plantilla_campo_propio_lista(text, boolean),
                          public.plantilla_campo_propio_valida(text, jsonb),
                          public.plantilla_campos_cx_publicos(text, uuid) to authenticated;
