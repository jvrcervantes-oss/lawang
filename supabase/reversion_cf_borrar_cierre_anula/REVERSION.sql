-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- VUELTA ATRAS de la migracion 20261014210000 «cf_borrar_cierre_anula_solo_admin» (14-oct-2026, Backend, bloque B).
-- REABRE lo que cerro: un agente sin la herramienta Contratos vuelve a poder borrar su operacion; el «no existe» frente al «es de
-- otra persona» con su numero vuelve a ser un oraculo; un agente vuelve a borrar una operacion con recibis o documentos enviados,
-- a cerrar un contrato como «firmado a mano» y a anular un recibi o un documento enviado; y «ya está anulado» vuelve a salir antes
-- del permiso. SOLO con OK del owner, y avisando a Seguridad.
-- Deja las tres funciones con el texto EXACTO que tenian en el vivo el 14-oct-2026 (pg_get_functiondef leido en solo lectura en la
-- sesion 1014-2040, cuerpos en LF) y lo comprueba al final por md5 (sin retornos de carro, por si el fichero se saca con CRLF).
-- create or replace conserva dueno y permisos. No toca datos: lo borrado o anulado mientras estuvo aplicada se queda como esta.
-- Ensayada en rama despues de la prueba de la migracion: supabase/pruebas/cf_vuelta.py ejecuta ESTE fichero y compara con el vivo.
-- destructivo-ok: reemplaza tres funciones con el mismo tipo de retorno (borrar_operacion ya llevaba sus delete); no borra nada

set local lock_timeout = '5s';

-- ============================================================ borrar_operacion(uuid), texto vivo de antes
CREATE OR REPLACE FUNCTION public.borrar_operacion(p_contrato_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if not public.es_agente() then
    raise exception 'no autorizado';
  end if;

  select array_agg(c.id) into ids
    from public.contratos c
   where c.id = p_contrato_id or c.contrato_padre_id = p_contrato_id;
  if ids is null then
    raise exception 'esa operacion no existe';
  end if;

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
end $function$
;

-- ============================================================ agente_escribe_fichero_contrato(text), texto vivo de antes
CREATE OR REPLACE FUNCTION public.agente_escribe_fichero_contrato(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.es_agente() and exists (
    select 1 from public.contratos c
     where coalesce(c.bloqueado, false) = false
       and public.puede_ver_contrato(c.id)
       and (p_name = c.numero || '_manual.pdf'
            or (p_name = 'pendientes/' || c.id::text || '.html'
                and not exists (select 1 from public.contrato_firmas f
                                 where f.contrato_id = c.id and f.estado = 'firmado'))))
$function$
;

-- ============================================================ factura_anula(uuid), texto vivo de antes
CREATE OR REPLACE FUNCTION public.factura_anula(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  if v_old.anulada then raise exception 'El documento % ya está anulado', v_old.numero using errcode = '22023'; end if;
  if not public._factura_puede_editar(v_old) then
    raise exception 'No puedes anular este documento' using errcode = '42501';
  end if;
  update public.facturas f set anulada = true where f.id = p_id;
end $function$
;


do $comprueba$
begin
  if (select count(*) from pg_proc p
       where (p.oid = 'public.borrar_operacion(uuid)'::regprocedure
              and md5(replace(pg_get_functiondef(p.oid), chr(13), '')) = '3b410ba14fd7280ae5699df39640c126')
          or (p.oid = 'public.agente_escribe_fichero_contrato(text)'::regprocedure
              and md5(replace(pg_get_functiondef(p.oid), chr(13), '')) = 'c7f561a699d8bb464c50132bf6546101')
          or (p.oid = 'public.factura_anula(uuid)'::regprocedure
              and md5(replace(pg_get_functiondef(p.oid), chr(13), '')) = '56a267446fea46f99b941a299806c8ba')) <> 3 then
    raise exception 'reversion cf_borrar_cierre_anula: alguna funcion no queda con el texto vivo de antes (md5); no se revierte nada';
  end if;
  if (select count(*) from pg_proc p
       where p.oid in ('public.borrar_operacion(uuid)'::regprocedure, 'public.agente_escribe_fichero_contrato(text)'::regprocedure,
                       'public.factura_anula(uuid)'::regprocedure)
         and p.prosecdef and 'search_path=""' = any (p.proconfig)
         and not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute')
         and not has_function_privilege('public', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')) <> 3 then
    raise exception 'reversion cf_borrar_cierre_anula: alguna funcion pierde DEFINER, search_path o sus permisos; no se revierte nada';
  end if;
end $comprueba$;
