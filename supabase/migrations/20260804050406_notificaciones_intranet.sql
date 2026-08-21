-- destructivo-ok: los unicos `drop` son `drop policy/trigger if exists` de objetos
-- que esta misma migracion vuelve a crear a continuacion (idempotencia). No borra
-- tablas, ni columnas, ni datos.
create table if not exists public.notificaciones (
  id           uuid primary key default gen_random_uuid(),
  tipo         text not null,
  titulo       text not null,
  detalle      text,
  destinatario text,
  contrato_id  uuid references public.contratos(id) on delete cascade,
  enlace       text,
  creado_en    timestamptz not null default now()
);
comment on table public.notificaciones is
  'Avisos de la intranet. Los escriben disparadores, nunca la aplicacion. Los vencimientos NO viven aqui: se calculan al leer.';
create index if not exists notificaciones_para_idx on public.notificaciones (destinatario, creado_en desc);
create index if not exists notificaciones_recientes_idx on public.notificaciones (creado_en desc);

alter table public.notificaciones enable row level security;
drop policy if exists "cada uno ve lo suyo, el admin todo" on public.notificaciones;
create policy "cada uno ve lo suyo, el admin todo" on public.notificaciones
  for select to authenticated
  using ( public.es_admin() or public.es_suyo(destinatario) );

alter table public.usuarios add column if not exists notif_visto_hasta timestamptz;

create or replace function public.marcar_notificaciones_leidas()
returns timestamptz
language sql security definer set search_path = public as $$
  update public.usuarios set notif_visto_hasta = now()
   where user_id = (select auth.uid())
  returning notif_visto_hasta;
$$;
revoke execute on function public.marcar_notificaciones_leidas() from public;
grant execute on function public.marcar_notificaciones_leidas() to authenticated;

create or replace function public.anotar_aviso(
  p_tipo text, p_titulo text, p_detalle text,
  p_destinatario text, p_contrato uuid, p_enlace text)
returns void
language sql security definer set search_path = public as $$
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace)
  values (p_tipo, p_titulo, p_detalle, nullif(btrim(coalesce(p_destinatario,'')),''), p_contrato, p_enlace);
$$;
revoke execute on function public.anotar_aviso(text,text,text,text,uuid,text) from public, authenticated;

create or replace function public.trg_aviso_contrato_firmado()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if coalesce(new.bloqueado,false) and not coalesce(old.bloqueado,false) then
      perform anotar_aviso('contrato_firmado',
        coalesce(new.numero,'Contrato') || ' firmado',
        coalesce(new.comprador_nombre,'sin comprador') || coalesce(' · ' || new.proyecto_nombre, ''),
        new.creado_por, new.id, '/operaciones/?contrato=' || new.id);
    end if;
  exception when others then
    raise warning 'aviso contrato_firmado (%) no se pudo anotar: %', new.id, sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists trg_avisa_contrato_firmado on public.contratos;
create trigger trg_avisa_contrato_firmado
after update of bloqueado on public.contratos
for each row execute function public.trg_aviso_contrato_firmado();

create or replace function public.trg_aviso_firma_enviada()
returns trigger language plpgsql security definer set search_path = public as $$
declare c record;
begin
  begin
    select numero, creado_por, proyecto_nombre into c from contratos where id = new.contrato_id;
    perform anotar_aviso('firma_enviada',
      'Enlace de firma enviado · ' || coalesce(c.numero,'sin nº'),
      coalesce(new.firmante_nombre,'firmante')
        || coalesce(' · caduca el ' || to_char(new.expira_en,'DD/MM/YYYY'), ''),
      c.creado_por, new.contrato_id, '/operaciones/?contrato=' || new.contrato_id);
  exception when others then
    raise warning 'aviso firma_enviada (%) no se pudo anotar: %', new.id, sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists trg_avisa_firma_enviada on public.contrato_firmas;
create trigger trg_avisa_firma_enviada
after insert on public.contrato_firmas
for each row execute function public.trg_aviso_firma_enviada();

create or replace function public.trg_aviso_factura()
returns trigger language plpgsql security definer set search_path = public as $$
declare c record; v_emitido numeric;
begin
  begin
    if coalesce(new.anulada,false) or new.tipo = 'proforma' then return new; end if;
    select numero, creado_por, precio_total, moneda, comprador_nombre
      into c from contratos where id = new.contrato_id;
    perform anotar_aviso('factura_emitida',
      'Factura ' || coalesce(new.numero,'sin nº') || ' emitida',
      coalesce(new.cliente_nombre,'') || ' · ' ||
        trim(to_char(coalesce(new.total,0),'FM999G999G990D00')) || ' ' || coalesce(new.moneda,''),
      coalesce(new.creado_por, c.creado_por), new.contrato_id,
      case when new.contrato_id is null then '/facturas/'
           else '/operaciones/?contrato=' || new.contrato_id end);
    if c.precio_total is not null and c.precio_total > 0 then
      select coalesce(sum(total),0) into v_emitido from facturas
       where contrato_id = new.contrato_id and not coalesce(anulada,false) and tipo <> 'proforma';
      if v_emitido >= c.precio_total then
        perform anotar_aviso('operacion_saldada',
          coalesce(c.numero,'Contrato') || ' saldado',
          coalesce(c.comprador_nombre,'') || ' · lo emitido cubre ya el precio pactado',
          c.creado_por, new.contrato_id, '/operaciones/?contrato=' || new.contrato_id);
      end if;
    end if;
  exception when others then
    raise warning 'aviso factura (%) no se pudo anotar: %', new.id, sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists trg_avisa_factura on public.facturas;
create trigger trg_avisa_factura
after insert on public.facturas
for each row execute function public.trg_aviso_factura();

create or replace function public.trg_aviso_unidad()
returns trigger language plpgsql security definer set search_path = public as $$
declare c record; v_texto text;
begin
  begin
    if new.estado is not distinct from old.estado then return new; end if;
    v_texto := case new.estado
      when 'reservada'  then 'reservada'
      when 'vendida'    then 'vendida'
      when 'disponible' then 'vuelve a estar disponible'
      else null end;
    if v_texto is null then return new; end if;
    select numero, creado_por into c from contratos
     where id = coalesce(new.contrato_id, old.contrato_id);
    perform anotar_aviso('unidad_' || new.estado,
      'Parcela ' || coalesce(new.codigo,'sin código') || ' ' || v_texto,
      coalesce(new.proyecto,'') || coalesce(' · ' || c.numero, ''),
      c.creado_por, coalesce(new.contrato_id, old.contrato_id), '/unidades/');
  exception when others then
    raise warning 'aviso unidad (%) no se pudo anotar: %', new.id, sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists trg_avisa_unidad on public.unidades;
create trigger trg_avisa_unidad
after update of estado on public.unidades
for each row execute function public.trg_aviso_unidad();;
