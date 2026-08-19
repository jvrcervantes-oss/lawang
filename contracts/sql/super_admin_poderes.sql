-- ════════════════════════════════════════════════════════════════════════════
-- LAW-71 · PODERES REALES DE SUPER_ADMIN — 19-ago-2026, encargo del owner
-- ════════════════════════════════════════════════════════════════════════════
-- Hasta hoy `super_admin` solo se saltaba dos cosas: el filtro por herramienta
-- (`puede()`) y el de proyectos. En todo lo demás iba EXACTAMENTE igual que un
-- admin, porque `es_suyo()` y `es_admin()` los tratan como el mismo rol. El
-- owner pidió lo contrario: cosas que él pueda hacer y los demás no.
--
-- LA REGLA QUE ORDENA TODO ESTO: un poder sin registro no es un permiso, es un
-- agujero. Cada freno que se salta y cada borrado dejan rastro — el borrado en
-- `public.borrados` (la fila entera, recuperable) y el salto en
-- `contrato_eventos`, que es donde el modal «Registro» ya mira.
--
-- Lo que NO se toca: `es_suyo()`/`es_admin()` siguen incluyendo a super_admin,
-- así que todo lo que ya podía un admin lo sigue pudiendo. Aquí solo se AÑADE
-- por arriba, salvo un caso marcado abajo (borrar facturas con dinero
-- aplicado), que baja de admin a super_admin a propósito.

-- ════════════════════════════════════════════════════════════════════════════
-- 1) LA CAJA NEGRA: nada se borra sin dejar copia
-- ════════════════════════════════════════════════════════════════════════════
-- El 18-ago se borraron 7 contratos vacíos y la copia se hizo A MANO en un
-- .json de Backups. Eso no es un procedimiento: es alguien acordándose. Con
-- «borrar de verdad» encima de contratos firmados, la copia tiene que ser parte
-- del borrado o no existe.
create table if not exists public.borrados (
  id          uuid primary key default gen_random_uuid(),
  tabla       text        not null,
  fila_id     uuid,
  numero      text,
  fila        jsonb       not null,
  quien       text,
  borrado_en  timestamptz not null default now()
);
create index if not exists borrados_tabla_fecha on public.borrados (tabla, borrado_en desc);

alter table public.borrados enable row level security;
-- Solo lectura, y solo para el super admin: aquí dentro está el contenido
-- íntegro de documentos borrados, incluidos los datos personales que llevaban.
drop policy if exists "super admin lee borrados" on public.borrados;
create policy "super admin lee borrados" on public.borrados
  for select using (public.es_super_admin());
-- Sin policy de INSERT/UPDATE/DELETE a propósito: escribe el trigger, que es
-- definer. Que nadie pueda editar la caja negra desde la API es la mitad de su
-- valor.

create or replace function public.trg_guarda_antes_de_borrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quien text := (select auth.email());
begin
  insert into public.borrados (tabla, fila_id, numero, fila, quien)
  values (tg_table_name, old.id,
          case when to_jsonb(old) ? 'numero' then to_jsonb(old)->>'numero' end,
          to_jsonb(old), v_quien);

  /* Una factura con cobros aplicados NO se podia borrar ni siendo super admin:
     la clave ajena de recibi_aplicaciones lo impedia y el error salia en crudo.
     Lo destapo la propia prueba de LAW-71. «Borrar de verdad» tiene que
     llevarse las dependencias, y por eso van ANTES a la caja negra: sin esa
     copia, borrar una factura desharia en silencio la atribucion de un cobro. */
  if tg_table_name = 'facturas' then
    if exists (select 1 from public.recibi_aplicaciones ra
                where ra.factura_id = old.id or ra.recibi_id = old.id) then
      if not public.es_super_admin() then
        raise exception 'esta factura tiene cobros aplicados: solo un super admin puede borrarla, y se lleva sus aplicaciones'
          using errcode = '23503';
      end if;
      insert into public.borrados (tabla, fila_id, numero, fila, quien)
      select 'recibi_aplicaciones', ra.id, null, to_jsonb(ra), v_quien
        from public.recibi_aplicaciones ra
       where ra.factura_id = old.id or ra.recibi_id = old.id;
      delete from public.recibi_aplicaciones ra
       where ra.factura_id = old.id or ra.recibi_id = old.id;
    end if;
  end if;

  return old;
end $$;

drop trigger if exists trg_guarda_antes_de_borrar on public.contratos;
create trigger trg_guarda_antes_de_borrar before delete on public.contratos
  for each row execute function public.trg_guarda_antes_de_borrar();

drop trigger if exists trg_guarda_antes_de_borrar on public.facturas;
create trigger trg_guarda_antes_de_borrar before delete on public.facturas
  for each row execute function public.trg_guarda_antes_de_borrar();

-- ════════════════════════════════════════════════════════════════════════════
-- 2) EL RASTRO DE CADA SALTO
-- ════════════════════════════════════════════════════════════════════════════
-- ⚠️ `contrato_eventos.evento` es una LISTA CERRADA por CHECK, y esto mordió por
-- TERCERA vez al escribir LAW-71: los eventos nuevos no estaban en el CHECK, así
-- que la edición privilegiada fallaba entera y el mensaje hablaba de una
-- restricción, no de lo que se estaba haciendo. La lista vive AQUÍ desde hoy y
-- la vigila `contracts/eventos.test.js`: quien añada un evento en código y no
-- aquí, no llega a producción.
alter table public.contrato_eventos drop constraint if exists contrato_eventos_evento_check;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check
  check (evento = any (array[
    'creado','editado','tipo_cambiado','enviado_a_firma','firma_abierta','firma_recogida',
    'firma_anulada','firmado_del_todo','desbloqueado','traspaso',
    'editado_estando_firmado','factura_sin_bloquear','cobro_a_factura_huerfana',
    'cobro_a_otro_comprador','comprador_sin_ficha','factura_borrada','contrato_borrado'
  ]));

comment on constraint contrato_eventos_evento_check on public.contrato_eventos is
  'Lista cerrada de eventos. Al anadir uno nuevo en codigo hay que anadirlo AQUI: si no, la escritura falla y el sintoma aparece lejos de la causa. Lo vigila tools/test.py via contracts/eventos.test.js.';

create or replace function public.registra_privilegio(p_contrato uuid, p_evento text, p_detalle jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  select p_contrato, p_evento, p_detalle, (select auth.email())
   where p_contrato is not null;
$$;
revoke all on function public.registra_privilegio(uuid, text, jsonb) from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 3) EDITAR (Y DESBLOQUEAR) UN CONTRATO FIRMADO
-- ════════════════════════════════════════════════════════════════════════════
-- La policy vieja exige `bloqueado = false`: un contrato firmado no lo edita
-- NADIE, ni un admin. Ahora el super admin sí — y con eso puede además
-- devolverlo a `bloqueado = false`, que era el camino sin vuelta que señaló el
-- owner. Todo lo demás de la policy se conserva palabra por palabra.
drop policy if exists "el autor o un admin editan contratos no bloqueados" on public.contratos;
create policy "el autor o un admin editan contratos no bloqueados" on public.contratos
  for update
  using (
    public.es_super_admin()
    or ((bloqueado = false) and public.es_agente() and public.puede('contratos')
        and public.es_suyo(creado_por) and public.puede_proyecto_de(datos, proyecto_nombre))
  )
  with check (
    public.es_super_admin()
    or (public.es_agente() and public.puede('contratos') and public.puede_proyecto_de(datos, proyecto_nombre))
  );

-- Y queda escrito quién tocó un contrato firmado, y si lo desbloqueó.
create or replace function public.trg_registra_edicion_privilegiada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(old.bloqueado, false) then
    perform public.registra_privilegio(new.id,
      case when coalesce(new.bloqueado, false) then 'editado_estando_firmado' else 'desbloqueado' end,
      jsonb_build_object('numero', old.numero, 'bloqueado_antes', old.bloqueado,
                         'bloqueado_despues', new.bloqueado));
  end if;
  return new;
end $$;

drop trigger if exists trg_registra_edicion_privilegiada on public.contratos;
create trigger trg_registra_edicion_privilegiada after update on public.contratos
  for each row when (coalesce(old.bloqueado, false)) execute function public.trg_registra_edicion_privilegiada();

-- ════════════════════════════════════════════════════════════════════════════
-- 4) BORRAR FACTURAS: el dinero baja a super_admin
-- ════════════════════════════════════════════════════════════════════════════
-- ⚠️ ÚNICO SITIO DONDE UN ADMIN PIERDE ALGO, y es a propósito. La policy vieja
-- era `es_admin()` a secas: cualquiera de los seis admins podía borrar una
-- factura ANULADA o una que ya tuviera cobros aplicados, y con ella el rastro
-- de ese dinero. Ahora eso es del super admin; lo demás sigue igual.
drop policy if exists "borrar facturas" on public.facturas;
create policy "borrar facturas" on public.facturas
  for delete using (
    public.es_super_admin()
    or (public.es_admin()
        and coalesce(anulada, false) = false
        and not exists (select 1 from public.recibi_aplicaciones ra
                         where ra.factura_id = facturas.id or ra.recibi_id = facturas.id))
  );

-- ════════════════════════════════════════════════════════════════════════════
-- 5) LOS FRENOS DE HOY, SALTABLES SOLO POR ÉL Y DEJANDO RASTRO
-- ════════════════════════════════════════════════════════════════════════════
-- 5a) Facturar un contrato sin bloquear (regla de esta misma mañana).
create or replace function public.trg_factura_exige_contrato_bloqueado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bloqueado boolean;
  v_numero    text;
begin
  if new.tipo is distinct from 'factura' then return new; end if;

  if tg_op = 'UPDATE'
     and old.tipo is not distinct from new.tipo
     and old.contrato_id is not distinct from new.contrato_id then
    return new;
  end if;

  if new.contrato_id is null then return new; end if;

  select c.bloqueado, c.numero into v_bloqueado, v_numero
    from public.contratos c where c.id = new.contrato_id;

  if not coalesce(v_bloqueado, false) then
    -- LAW-71: el super admin pasa, pero queda escrito en el historial del
    -- contrato. Sin esta línea el poder sería invisible, que es como se
    -- convierte en un agujero.
    if public.es_super_admin() then
      perform public.registra_privilegio(new.contrato_id, 'factura_sin_bloquear',
        jsonb_build_object('factura', new.numero, 'total', new.total, 'moneda', new.moneda));
      return new;
    end if;
    raise exception 'el contrato % no esta bloqueado: una factura se emite cuando el contrato esta firmado y cerrado. Para cobrar antes, emite una proforma y su recibi',
      coalesce(v_numero, '?') using errcode = '23514';
  end if;

  return new;
end $$;

-- 5b) Aplicar un cobro a la factura de otro comprador (LAW-41(2), de hoy).
--     Se rehace `guardar_recibi` entera porque plpgsql no se parchea a trozos;
--     es idéntica a la de esta mañana salvo los dos bloques marcados.
create or replace function public.guardar_recibi(p_id uuid, p_factura jsonb, p_aplicaciones jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_numero text;
  v_aplicacion jsonb;
  v_contrato_id uuid;
  v_justificante text;
  v_factura_id uuid;
  v_factura_numero text;
  v_factura_contrato uuid;
begin
  if not (public.es_agente() and public.puede('facturas')) then
    raise exception 'sin permiso para crear recibis' using errcode = '42501';
  end if;

  v_contrato_id := nullif(p_factura->>'contrato_id', '')::uuid;
  v_justificante := nullif(p_factura->>'justificante_path', '');
  if v_contrato_id is null then
    raise exception 'el recibi necesita un contrato' using errcode = '23514';
  end if;
  if v_justificante is null then
    raise exception 'el recibi necesita un justificante de pago adjunto' using errcode = '23514';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'justificantes' and name = v_justificante) then
    raise exception 'el justificante adjunto no existe en el almacenamiento' using errcode = '23514';
  end if;
  if jsonb_typeof(p_aplicaciones) <> 'array' or jsonb_array_length(p_aplicaciones) = 0 then
    raise exception 'el recibi necesita al menos una factura que salde' using errcode = '23514';
  end if;

  if p_id is null then
    insert into public.facturas
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
       total, moneda, fecha_emision, justificante_path, datos)
    values
      ('recibi', p_factura->>'sociedad', p_factura->>'cliente_nombre', p_factura->>'proyecto_nombre',
       p_factura->>'contrato_numero', v_contrato_id, (p_factura->>'total')::numeric, p_factura->>'moneda',
       nullif(p_factura->>'fecha_emision','')::date, v_justificante, p_factura->'datos')
    returning id, numero into v_id, v_numero;
  else
    update public.facturas set
      sociedad = p_factura->>'sociedad', cliente_nombre = p_factura->>'cliente_nombre',
      proyecto_nombre = p_factura->>'proyecto_nombre', contrato_numero = p_factura->>'contrato_numero',
      contrato_id = v_contrato_id, total = (p_factura->>'total')::numeric, moneda = p_factura->>'moneda',
      fecha_emision = nullif(p_factura->>'fecha_emision','')::date, justificante_path = v_justificante,
      datos = p_factura->'datos'
    where id = p_id and tipo = 'recibi' and anulada = false and public.es_suyo(creado_por)
    returning id, numero into v_id, v_numero;
    if v_id is null then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    delete from public.recibi_aplicaciones where recibi_id = v_id;
  end if;

  for v_aplicacion in select * from jsonb_array_elements(p_aplicaciones) loop
    v_factura_id := (v_aplicacion->>'factura_id')::uuid;

    select f.numero, f.contrato_id into v_factura_numero, v_factura_contrato
      from public.facturas f
     where f.id = v_factura_id
       and f.tipo = 'factura' and not coalesce(f.anulada, false);
    if not found then
      raise exception 'la aplicacion referencia una factura invalida o anulada' using errcode = '23514';
    end if;

    if v_factura_contrato is null then
      -- LAW-71: el super admin puede repartir contra una factura huerfana (las
      -- 3 de LAW-38), pero queda escrito.
      if public.es_super_admin() then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_factura_huerfana',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero));
      else
        raise exception 'la factura % no cuelga de ningun contrato: no se le puede aplicar un cobro (LAW-38)',
          coalesce(v_factura_numero, '?') using errcode = '23514';
      end if;
    elsif not public.contratos_mismo_comprador(v_contrato_id, v_factura_contrato) then
      if public.es_super_admin() then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_otro_comprador',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero,
                             'importe', v_aplicacion->>'importe'));
      else
        raise exception 'la factura % es de otro comprador que el recibi', coalesce(v_factura_numero, '?')
          using errcode = '23514';
      end if;
    end if;

    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, v_factura_id, (v_aplicacion->>'importe')::numeric, (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$$;

revoke all on function public.guardar_recibi(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.guardar_recibi(uuid, jsonb, jsonb) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 6) VER Y AUDITAR: el historial de privilegios, en un solo sitio
-- ════════════════════════════════════════════════════════════════════════════
create or replace view public.privilegios_ejercidos as
select e.creado_en, e.quien, e.evento, c.numero as contrato, e.detalle
  from public.contrato_eventos e
  left join public.contratos c on c.id = e.contrato_id
 where e.evento in ('editado_estando_firmado','desbloqueado','factura_sin_bloquear',
                    'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha')
union all
select b.borrado_en, b.quien, 'borrado_' || b.tabla, b.numero,
       jsonb_build_object('fila_id', b.fila_id)
  from public.borrados b;

alter view public.privilegios_ejercidos set (security_invoker = true);
grant select on public.privilegios_ejercidos to authenticated;
