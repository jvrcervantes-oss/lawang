-- destructivo-ok: el unico DROP es la firma vieja (3 argumentos) de contrato_firmas_anula, que se recrea en la misma migracion con un 4o argumento opcional; no toca datos.
-- Frontera frontend/backend — contratos, pieza 5, pasos C y D (26-sep-2026, LAW-336; plan corregido
-- por la revisión previa #120, y hallazgos de la consulta de deploy de E+B). SOLO AÑADE funciones y
-- columnas; quitar a la pantalla las policies de storage va en la migración siguiente, cuando la
-- pantalla servida ya use la edge `ficheros-contrato`.
--
-- C) Enviar a firma: el TOKEN lo generaba el navegador (y guardaba él su hash). Ahora lo genera la
--    base: `contrato_envia_firma` anula los enlaces pendientes y crea el nuevo EN UNA transacción
--    (antes eran dos llamadas sueltas), devuelve el enlace una vez y guarda `snapshot_hash` — el hash
--    del documento que se va a firmar, que calcula la edge leyendo el bucket (Postgres no lee bytes
--    de Storage). firma-submit se niega a estampar si el documento ya no cuadra (Legal #120, ALTA).
--    La URL base del enlace la fija el servidor. `enlace_firma` se sigue guardando (owner, 1-sep).
-- C) PDF firmado a mano: el hash lo calculaba el navegador y él mismo bloqueaba el contrato con la
--    ruta y el hash que quisiera. Ahora `contrato_cierra_manual` solo la llama la edge (service_role)
--    con el hash que calcula ella sobre el fichero subido; cierra y anula los enlaces vivos a la vez.
-- Legal (consulta de deploy E+B, MEDIA): anular una firma YA DADA exige justificación escrita, que se
--    guarda; el código de motivo solo no explica por qué se revocó un consentimiento.

alter table public.contrato_firmas
  add column if not exists snapshot_hash         text,
  add column if not exists anulado_justificacion text;

-- anular: misma función con la justificación obligatoria cuando se anula una firma dada
drop function if exists public.contrato_firmas_anula(uuid, text, boolean);
create or replace function public.contrato_firmas_anula(p_contrato uuid, p_motivo text,
                                                        p_incluir_firmadas boolean default false,
                                                        p_justificacion text default null)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_n int;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_just text := nullif(btrim(coalesce(p_justificacion, '')), '');
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_agente() or not exists (
       select 1 from public.contratos c
        where c.id = p_contrato and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))) then
    raise exception 'No puedes anular las firmas de este contrato' using errcode = '42501';
  end if;
  if v_motivo is null or v_motivo not in ('editar', 'nuevo_enlace', 'cierre_manual') then
    raise exception 'Motivo de anulación no válido' using errcode = '22023';
  end if;
  if coalesce(p_incluir_firmadas, false) then
    if not public.es_super_admin() then
      raise exception 'Una firma ya dada no se anula: el cambio va por adenda (o lo reabre un super admin)'
        using errcode = '42501';
    end if;
    if v_just is null or length(v_just) < 10 then
      raise exception 'Para anular una firma ya dada escribe por qué (queda en el registro)' using errcode = '22023';
    end if;
  end if;

  update public.contrato_firmas f
     set estado = 'anulado', anulado_en = now(), anulado_por = (select auth.email()),
         anulado_motivo = v_motivo, anulado_justificacion = v_just
   where f.contrato_id = p_contrato
     and (f.estado = 'pendiente' or (coalesce(p_incluir_firmadas, false) and f.estado = 'firmado'));
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.contrato_firmas_anula(uuid, text, boolean, text) from public, anon;
grant execute on function public.contrato_firmas_anula(uuid, text, boolean, text) to authenticated;

-- permiso para mandar a firma + cuántos han firmado ya (la edge decide con esto si acepta un documento nuevo)
create or replace function public.contrato_firma_estado(p_contrato uuid)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select jsonb_build_object('numero', c.numero,
           'firmados', (select count(*) from public.contrato_firmas f where f.contrato_id = c.id and f.estado = 'firmado'))
    into v
    from public.contratos c
   where c.id = p_contrato and coalesce(c.bloqueado, false) = false
     and public.es_agente() and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id));
  if v is null then
    raise exception 'No puedes mandar a firma este contrato (no es tuyo o ya está cerrado)' using errcode = '42501';
  end if;
  return v;
end $$;
revoke all on function public.contrato_firma_estado(uuid) from public, anon;
grant execute on function public.contrato_firma_estado(uuid) to authenticated;

create or replace function public.contrato_envia_firma(p_contrato uuid, p_nombre text, p_email text,
                                                       p_rol text, p_orden integer, p_snapshot_hash text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_email  text := btrim(coalesce(p_email, ''));
  v_rol    text := btrim(coalesce(p_rol, ''));
  v_token  text;
  v_link   text;
  v_anul   int;
begin
  perform public.contrato_firma_estado(p_contrato);   -- permiso y contrato abierto (raise si no)
  if length(v_nombre) < 2 then raise exception 'Pon el nombre del comprador' using errcode = '22023'; end if;
  if v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Pon un email válido del comprador' using errcode = '22023'; end if;
  if v_rol !~ '^adquiriente_[0-9]+$' then raise exception 'Firmante no válido' using errcode = '22023'; end if;
  if coalesce(p_orden, 0) < 1 then raise exception 'Orden de firma no válido' using errcode = '22023'; end if;
  if coalesce(p_snapshot_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Falta el documento a firmar' using errcode = '22023'; end if;
  if exists (select 1 from public.contrato_firmas f
              where f.contrato_id = p_contrato and f.firmante_rol = v_rol and f.estado = 'firmado') then
    raise exception 'Ese firmante ya ha firmado este contrato' using errcode = '23505';
  end if;

  -- un solo enlace vivo por contrato (índice contrato_firmas_un_pendiente_por_rol, 28-jul)
  update public.contrato_firmas f
     set estado = 'anulado', anulado_en = now(), anulado_por = (select auth.email()), anulado_motivo = 'nuevo_enlace'
   where f.contrato_id = p_contrato and f.estado = 'pendiente';
  get diagnostics v_anul = row_count;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_link  := 'https://lawangproperties.com/contracts/firmar.html?t=' || v_token;
  insert into public.contrato_firmas (contrato_id, token_hash, firmante_nombre, firmante_email, firmante_rol,
                                      orden, snapshot_path, snapshot_hash, enlace_firma)
  values (p_contrato, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_nombre, v_email, v_rol,
          p_orden, 'pendientes/' || p_contrato::text || '.html', p_snapshot_hash, v_link);
  return jsonb_build_object('link', v_link, 'anulados', v_anul);
end $$;
revoke all on function public.contrato_envia_firma(uuid, text, text, text, integer, text) from public, anon;
grant execute on function public.contrato_envia_firma(uuid, text, text, text, integer, text) to authenticated;

-- Cierre con PDF firmado a mano: SOLO la edge (service_role), que ya comprobó el permiso con la sesión
-- del usuario y calculó el hash sobre el fichero subido. `p_actor` = email de la sesión verificada.
create or replace function public.contrato_cierra_manual(p_id uuid, p_path text, p_hash text, p_actor text)
returns integer
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  if coalesce(p_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Hash no válido' using errcode = '22023'; end if;
  update public.contratos c
     set bloqueado = true, pdf_firmado_path = p_path, pdf_firmado_hash = p_hash
   where c.id = p_id and coalesce(c.bloqueado, false) = false and c.pdf_firmado_path is null
     and p_path = c.numero || '_manual.pdf';
  if not found then
    raise exception 'El contrato ya está cerrado o ya tiene un PDF firmado' using errcode = '23514';
  end if;
  -- mismo barrido que firma-submit al cerrar: un enlace vivo tras el cierre dejaría firmar contra un contrato cerrado
  update public.contrato_firmas f
     set estado = 'anulado', anulado_en = now(), anulado_por = p_actor, anulado_motivo = 'cierre_manual'
   where f.contrato_id = p_id and f.estado = 'pendiente';
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.contrato_cierra_manual(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.contrato_cierra_manual(uuid, text, text, text) to service_role;
