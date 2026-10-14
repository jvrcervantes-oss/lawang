-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68). El maestro lleva borrar_operacion, factura_anula y
--   agente_escribe_fichero_contrato en erp/migraciones (b1_dinero, b9_cierre_global, f9_m2_visibilidad...): el porte de la parte
--   compartida va por su fila en contexto/pendientes.md de la agencia (la abre quien encarga, regla «arreglo compartido», 29-sep).
-- BORRAR UNA OPERACION CON COBROS, CERRAR «FIRMADO A MANO» Y ANULAR LO ENVIADO O COBRADO: SOLO ADMIN DE LA EMPRESA (14-oct-2026, Backend).
-- Bloque B del plan «arreglos seguros y reversibles de Contratos y Facturas» (revision previa de Backend #337 y de Seguridad #338, plan
--   cerrado). Decision del owner del 14-oct (~20:30) para el cierre manual; el resto, decision por defecto del CEO (agencia-81).
-- QUE HACE:
--   (i) borrar_operacion, en este orden:
--       1. exige la herramienta Contratos (_puede_herr('contratos')); antes bastaba con ser agente activo («no autorizado», sin codigo).
--          Medido el 14-oct: 1 agente activo no la tiene y pierde el borrado (lo dijo Backend en la revision previa).
--       2. existencia + visibilidad (puede_ver_contrato de la operacion pedida) con UN solo mensaje y un solo codigo (P0002) para «no
--          existe» y «no la ves». La existencia se mira aparte porque puede_ver_contrato da true a un admin con cualquier id no nulo.
--          Antes «esa operacion no existe» frente a «El contrato % ... es de otra persona» era un oraculo: confirmaba que un id existia
--          y daba su NUMERO a quien no lo ve.
--       3. autoria, COMO HOY (mismo texto): sin ser super admin de todas sus empresas, solo el autor de cada contrato, y ninguno
--          firmado. Un admin_empresa que NO es el autor sigue sin poder borrar (no cambia).
--       4. NUEVO: si la cadena tiene un recibi vivo (tipo recibi y no anulado: el mismo criterio que `recibis_vivos` de _sc_huella) o
--          un documento ENVIADO al cliente (enviada = true, de cualquier tipo, factura, proforma o recibi, y AUNQUE este anulado: es la
--          prueba de lo que se le mando), hace falta ser admin de TODAS las empresas de la cadena:
--          `not exists (... not es_admin_de(p2.empresa))`, el mismo patron que la comprobacion de super_admin_de del paso 3. Mensaje
--          propio, 42501. Medido el 14-oct (solo lectura): 94 operaciones raiz quedan detras de esta regla.
--       Ademas, tras el paso 2 se bloquean (for update) los contratos de la cadena: un recibi que se guarde a la vez espera al
--       borrado y su clave foranea ya no casa; sin el cerrojo la regla 4 se podia saltar por milisegundos. resolver_solicitud_cambio
--       ya los bloqueaba en su misma transaccion antes de llamar.
--       NADA se basa en auth.email(): el llamador de Telegram (resolver_solicitud_cambio) entra con el uid del super admin que
--       aprueba y con un CORREO FALSO («SC-n · pedido por ... vía Telegram»); por uid sigue pasando los cuatro pasos.
--       Llamadores (los dos siguen): v4 intranet/v4/assets/datos.js:1073 (sesion del usuario) y resolver_solicitud_cambio.
--  (ii) agente_escribe_fichero_contrato, rama `<numero>_manual.pdf` (la que pregunta la edge ficheros-contrato:267 con la sesion del
--       usuario antes de dar la URL de subida y antes de cerrar): ademas de ver el contrato, ser admin de su empresa,
--       es_admin_de(_empresa_doc(null, c.id)). contrato_cierra_manual NO se toca: solo la llama la edge con service_role.
--       La rama `pendientes/` (enviar a firmar) queda igual: los agentes siguen enviando a firmar.
-- (iii) factura_anula: anular un RECIBI o un documento ENVIADO solo lo hace un admin de la empresa del documento,
--       es_admin_de(_empresa_doc(proyecto_id, contrato_id)). Lo demas como hoy (un borrador lo anula su autor, su manager o el admin).
--       El permiso va ANTES del mensaje «El documento % ya está anulado» (hoy daba el numero de un documento ajeno a cualquiera con
--       su uuid): se mira con la fila como si no estuviera anulada, para que quien SI podria anularla siga leyendo «ya está anulado».
--       Orden: existe -> permiso de siempre -> regla nueva -> ya anulado -> update. Queda, como hoy, «Ese documento ya no existe»
--       frente a «No puedes anular» para un uuid: solo le sirve a quien ya tiene el uuid (no se lista ni se adivina).
--       Medido el 14-oct (solo lectura): 128 recibis vivos y 54 facturas o proformas enviadas sin anular quedan detras de la regla.
-- LO QUE NO HACE: no toca datos, ni contrato_cierra_manual, ni la pantalla. La pantalla sigue ofreciendo «Subir firmado» y «Anular»
--   a un agente, y ahora el servidor se lo niega con su mensaje (la edge devuelve 403 `sin_permiso_sobre_este_contrato`): ocultarlo
--   para quien no es admin es trabajo de Frontend (regla doble, LAW-51 punto 5), en otra copia.
-- Las tres se REESCRIBEN ENTERAS desde su definicion viva (cortas: 3,0 KB, 0,6 KB y 0,7 KB), con este md5 de pg_get_functiondef
--   medido en el vivo el 14-oct-2026 en la sesion 1014-2040 (solo lectura, cuerpos en LF, sin retorno de carro):
--     borrar_operacion(uuid)                  3b410ba14fd7280ae5699df39640c126
--     agente_escribe_fichero_contrato(text)   c7f561a699d8bb464c50132bf6546101
--     factura_anula(uuid)                     56a267446fea46f99b941a299806c8ba
--   El bloque $antes$ hace de «marca y raise»: si alguna ya no tiene ese md5 (alguien la cambio entre medias) y tampoco lleva ya este
--   arreglo, lanza y no se aplica NADA (no se pisa un cambio ajeno). Idempotente: aplicada dos veces, la segunda reescribe lo mismo.
--   Las tres conservan SECURITY DEFINER y search_path = ''; create or replace conserva dueno y permisos (anon no, authenticated si,
--   public no, service_role si, medido el 14-oct), y el bloque $cierre$ lo comprueba al final.
-- destructivo-ok: reemplaza tres funciones con el mismo tipo de retorno; los delete son los que ya tenia borrar_operacion (el borrado
--   de la operacion que el usuario pide), sin cambiar a que filas alcanzan
-- REVERTIR: supabase/reversion_cf_borrar_cierre_anula/REVERSION.sql (los tres textos vivos de antes, tal cual; reabre el oraculo y
--   deja a un agente borrar y anular lo cobrado o enviado: solo con OK del owner y avisando a Seguridad).
-- Prueba: supabase/pruebas/cf_borrar_cierre_anula.sql (crea contratos: SOLO en rama) y cf_vuelta.py (la reversion real, en rama):
--   python erp/rama_prueba.py lawang --lawang <copia> --aplica 20261014210000_cf_borrar_cierre_anula_solo_admin.sql
--          --prueba cf_borrar_cierre_anula.sql,cf_vuelta.py

-- create or replace function no toma cerrojo de tabla, pero si espera a quien este ejecutando la funcion: mejor fallar limpio a los 5 s.
set local lock_timeout = '5s';

-- ============================================================ 0. Marca y raise: el vivo es el que se leyo (o ya lleva el arreglo)
do $antes$
declare x record;
begin
  for x in select * from (values
             ('public.borrar_operacion(uuid)',                '3b410ba14fd7280ae5699df39640c126', 'solo la puede borrar un administrador de su empresa'),
             ('public.agente_escribe_fichero_contrato(text)', 'c7f561a699d8bb464c50132bf6546101', 'public.es_admin_de(public._empresa_doc(null, c.id))'),
             ('public.factura_anula(uuid)',                   '56a267446fea46f99b941a299806c8ba', 'v_chk.anulada := false')) t(f, m, marca)
  loop
    if md5(replace(pg_get_functiondef(x.f::regprocedure), chr(13), '')) <> x.m
       and position(x.marca in pg_get_functiondef(x.f::regprocedure)) = 0 then
      raise exception 'cf_borrar_cierre_anula: % no es la definicion viva leida el 14-oct (md5 distinto) ni lleva ya el arreglo; no se aplica nada', x.f;
    end if;
  end loop;
end $antes$;

-- ============================================================ (i) borrar_operacion
create or replace function public.borrar_operacion(p_contrato_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  ids        uuid[];
  n_cont     int;
  n_firmas   int;
  n_fact     int;
  n_devengos int;
  n_solic    int;
  bloqueado_ajeno text;
  d_blindado_id uuid;
  solicitudes_a_purgar uuid[];
begin
  -- 1. La herramienta (14-oct-2026, bloque B). Antes bastaba con ser agente activo.
  if not public._puede_herr('contratos') then
    raise exception 'No tienes la herramienta de Contratos: pídesela a un administrador en Usuarios.' using errcode = '42501';
  end if;

  -- 2. Existe Y la ves: un solo mensaje y un solo codigo para las dos cosas (cierra el oraculo de existencia y de numero).
  --    La existencia va aparte: puede_ver_contrato da true a un admin con cualquier id no nulo.
  if not exists (select 1 from public.contratos c where c.id = p_contrato_id)
     or not public.puede_ver_contrato(p_contrato_id) then
    raise exception 'Esa operación no existe o no tienes acceso a ella.' using errcode = 'P0002';
  end if;

  -- Cerrojo de la cadena: un recibi guardado a la vez espera al borrado (su clave foranea pide FOR KEY SHARE).
  perform 1 from public.contratos c
   where c.id = p_contrato_id or c.contrato_padre_id = p_contrato_id
     for update;

  select array_agg(c.id) into ids
    from public.contratos c
   where c.id = p_contrato_id or c.contrato_padre_id = p_contrato_id;
  if ids is null then
    raise exception 'Esa operación no existe o no tienes acceso a ella.' using errcode = 'P0002';
  end if;

  -- 3. Autoria, como hasta el 14-oct-2026 (mismo texto).
  if not (public.es_super_admin() or not exists (
       select 1 from public.contratos c2 left join public.proyectos p2 on p2.id = c2.proyecto_id
        where c2.id = any (ids) and not public.es_super_admin_de(p2.empresa))) then
    select c.numero into bloqueado_ajeno
      from public.contratos c
     where c.id = any(ids)
       and (coalesce(c.bloqueado,false) = true
            or c.creado_por is null
            or c.creado_por <> (select auth.email()))
     limit 1;
    if bloqueado_ajeno is not null then
      raise exception 'El contrato % esta firmado o es de otra persona: esta operacion solo la puede borrar un super admin', bloqueado_ajeno;
    end if;
  end if;

  -- 4. Con cobros o con algo ya enviado al cliente, solo un admin de TODAS las empresas de la cadena (14-oct-2026, bloque B).
  --    Recibi vivo = el criterio de `recibis_vivos` de _sc_huella; enviado = enviada, de cualquier tipo y aunque este anulado.
  if exists (select 1 from public.facturas f
              where f.contrato_id = any (ids)
                and ((f.tipo = 'recibi' and not coalesce(f.anulada, false)) or coalesce(f.enviada, false)))
     and exists (select 1 from public.contratos c2 left join public.proyectos p2 on p2.id = c2.proyecto_id
                  where c2.id = any (ids) and not public.es_admin_de(p2.empresa)) then
    raise exception 'Esta operación tiene un recibí vigente o un documento ya enviado al cliente: solo la puede borrar un administrador de su empresa. Pídeselo a un administrador.'
      using errcode = '42501';
  end if;

  select d.id into d_blindado_id
    from public.comisiones_devengadas d
    left join public.solicitudes_pago sp on sp.id = d.solicitud_id
   where d.contrato_raiz_id = any(ids)
     and (d.estado in ('pagada', 'en_disputa') or sp.estado in ('pagada', 'aprobada'))
   limit 1;
  if d_blindado_id is not null then
    raise exception 'Esta operacion tiene una comision pagada, en disputa o ya aprobada para pago (devengo %): no se puede borrar automaticamente, resuelvelo a mano', d_blindado_id;
  end if;

  update public.contrato_firmas set estado = 'anulado'
   where contrato_id = any(ids) and estado in ('pendiente','procesando');
  get diagnostics n_firmas = row_count;

  update public.facturas set anulada = true
   where contrato_id = any(ids) and coalesce(anulada,false) = false;
  get diagnostics n_fact = row_count;

  select array_agg(distinct d.solicitud_id) into solicitudes_a_purgar
    from public.comisiones_devengadas d
   where d.contrato_raiz_id = any(ids) and d.solicitud_id is not null;

  delete from public.comisiones_devengadas where contrato_raiz_id = any(ids);
  get diagnostics n_devengos = row_count;

  if solicitudes_a_purgar is not null then
    delete from public.solicitudes_pago where id = any(solicitudes_a_purgar);
    get diagnostics n_solic = row_count;
  else
    n_solic := 0;
  end if;

  delete from public.contratos where id = any(ids);
  get diagnostics n_cont = row_count;

  return jsonb_build_object(
    'contratos_borrados',   n_cont,
    'firmas_anuladas',      n_firmas,
    'facturas_anuladas',    n_fact,
    'comisiones_purgadas',  n_devengos,
    'solicitudes_purgadas', n_solic);
end $function$;

-- ============================================================ (ii) cierre manual «firmado a mano»: solo admin de la empresa del contrato
create or replace function public.agente_escribe_fichero_contrato(p_name text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select public.es_agente() and exists (
    select 1 from public.contratos c
     where coalesce(c.bloqueado, false) = false
       and public.puede_ver_contrato(c.id)
       and ((p_name = c.numero || '_manual.pdf'
             -- 14-oct-2026 (owner, bloque B): cerrar como «firmado a mano» solo lo hace un admin de la empresa del contrato
             and public.es_admin_de(public._empresa_doc(null, c.id)))
            or (p_name = 'pendientes/' || c.id::text || '.html'
                and not exists (select 1 from public.contrato_firmas f
                                 where f.contrato_id = c.id and f.estado = 'firmado'))))
$function$;

-- ============================================================ (iii) factura_anula
create or replace function public.factura_anula(p_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_old public.facturas%rowtype;
  v_chk public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  -- 14-oct-2026 (bloque B): el permiso va ANTES de «ya está anulado» (era un oraculo del numero). Se mira con la fila como si no
  -- estuviera anulada: _factura_puede_editar niega toda anulada salvo al super admin, y entonces quien SI podria anularla leeria
  -- «No puedes anular» en vez de «ya está anulado».
  v_chk := v_old;
  v_chk.anulada := false;
  if not public._factura_puede_editar(v_chk) then
    raise exception 'No puedes anular este documento' using errcode = '42501';
  end if;
  if (v_old.tipo = 'recibi' or coalesce(v_old.enviada, false))
     and not public.es_admin_de(public._empresa_doc(v_old.proyecto_id, v_old.contrato_id)) then
    raise exception 'Un recibí o un documento ya enviado al cliente solo lo puede anular un administrador de su empresa. Pídeselo a un administrador.'
      using errcode = '42501';
  end if;
  if v_old.anulada then raise exception 'El documento % ya está anulado', v_old.numero using errcode = '22023'; end if;
  update public.facturas f set anulada = true where f.id = p_id;
end $function$;

-- ============================================================ Comprobacion final: DEFINER, search_path y permisos como antes
-- Antes (vivo, 14-oct): las tres con prosecdef, search_path="", anon NO, authenticated SI, public NO, service_role SI.
do $cierre$
begin
  if (select count(*) from pg_proc p
       where p.oid in ('public.borrar_operacion(uuid)'::regprocedure, 'public.agente_escribe_fichero_contrato(text)'::regprocedure,
                       'public.factura_anula(uuid)'::regprocedure)
         and p.prosecdef and 'search_path=""' = any (p.proconfig)
         and not has_function_privilege('anon', p.oid, 'execute')
         and has_function_privilege('authenticated', p.oid, 'execute')
         and not has_function_privilege('public', p.oid, 'execute')
         and has_function_privilege('service_role', p.oid, 'execute')) <> 3 then
    raise exception 'cf_borrar_cierre_anula: alguna de las tres ha perdido DEFINER, search_path o sus permisos de antes; no se aplica nada';
  end if;
end $cierre$;
