-- destructivo-ok: los únicos `drop` son `drop policy/trigger if exists` de
-- objetos que este mismo fichero vuelve a crear tres líneas más abajo, para
-- poder reejecutarlo entero sin que falle. No borra ninguna tabla, ninguna
-- columna y ningún dato. El único UPDATE masivo es el de la siembra
-- (`notif_visto_hasta` donde es nulo), que rellena una columna recién creada.
-- ============================================================================
-- Notificaciones de la intranet — 4-ago-2026
-- ----------------------------------------------------------------------------
-- PETICIÓN DEL OWNER: «a los administradores deben salirle notificaciones de
-- todo lo que pasa pero a cada operador lo suyo. Si han firmado un contrato de
-- un agente, que le salga que ya está firmado». Y la duda: «¿es un servicio que
-- escucha siempre?».
--
-- NO HACE FALTA NINGÚN SERVICIO. Un contrato no se firma solo: alguien escribe
-- en `contratos`. El disparador corre DENTRO de esa misma escritura y deja el
-- aviso apuntado. Cuando el operador abre cualquier herramienta, la campana lee
-- lo suyo. Con la intranet cerrada no hay nada consumiendo.
--
-- DOS TIPOS DE AVISO, Y SOLO UNO SE GUARDA:
--   · HECHOS — «este contrato quedó firmado». Ocurrió en un instante y no vuelve
--     a ocurrir. Se guardan aquí.
--   · VENCIMIENTOS — «esta factura vence en 5 días». No es que haya pasado algo,
--     es que LLEVA pasando, y será mentira dentro de una semana. Se calculan al
--     leer (topbar.js), con la misma consulta que ya usa Vencimientos en
--     Operaciones. Guardarlos obligaría a un proceso diario que los repasara y
--     los borrara: justo el servicio encendido que se quería evitar.
--
-- REPARTO: `destinatario` es el email de `creado_por` del documento — el MISMO
-- campo con el que la RLS decide hoy quién puede editar qué. Un segundo criterio
-- acabaría desalineado del primero. `destinatario` nulo (los 13 contratos
-- anteriores a que existiera la columna) = solo lo ven los administradores, que
-- es donde debe ir: inventar un destinatario es peor que no mandarlo.
-- ============================================================================

create table if not exists public.notificaciones (
  id           uuid primary key default gen_random_uuid(),
  tipo         text not null,
  titulo       text not null,
  detalle      text,
  destinatario text,                      -- email; nulo = solo administradores
  contrato_id  uuid references public.contratos(id) on delete cascade,
  enlace       text,
  creado_en    timestamptz not null default now()
);

comment on table public.notificaciones is
  'Avisos de la intranet. Los escriben disparadores, nunca la aplicacion. Los vencimientos NO viven aqui: se calculan al leer.';
comment on column public.notificaciones.destinatario is
  'Email de creado_por del documento. Nulo = solo administradores.';

create index if not exists notificaciones_para_idx on public.notificaciones (destinatario, creado_en desc);
create index if not exists notificaciones_recientes_idx on public.notificaciones (creado_en desc);

-- ── quién ve qué ────────────────────────────────────────────────────────────
-- Solo SELECT. No hay policy de insert, update ni delete a propósito: los avisos
-- los escriben los disparadores (SECURITY DEFINER) y nadie más. Sin policy de
-- escritura, un operador no puede fabricarse un aviso ni borrar el que le
-- molesta, y eso no depende de que la interfaz no le ofrezca el botón.
alter table public.notificaciones enable row level security;
drop policy if exists "cada uno ve lo suyo, el admin todo" on public.notificaciones;
create policy "cada uno ve lo suyo, el admin todo" on public.notificaciones
  for select to authenticated
  using ( public.es_admin() or public.es_suyo(destinatario) );

-- ── hasta cuándo ha visto cada uno ──────────────────────────────────────────
-- Una marca de tiempo por persona, no una fila por aviso leído: lo que se pidió
-- es que el contador vuelva a cero al abrir el panel, no saber cuál de los
-- cuarenta avisos miró. Va en `usuarios` y NO en el navegador porque la suite se
-- usa desde el móvil y desde el escritorio: en localStorage, el mismo aviso
-- saldría sin leer en cada aparato.
alter table public.usuarios add column if not exists notif_visto_hasta timestamptz;

-- La RLS de `usuarios` solo deja editar al admin —y está bien, ahí viven el rol
-- y los permisos—, así que un agente no puede marcar sus propios avisos como
-- leídos. En vez de abrir esa tabla a escritura, una función que solo toca ESA
-- columna y solo de quien la llama.
create or replace function public.marcar_notificaciones_leidas()
returns timestamptz
language sql security definer set search_path = public as $$
  update public.usuarios set notif_visto_hasta = now()
   where user_id = (select auth.uid())
  returning notif_visto_hasta;
$$;
revoke execute on function public.marcar_notificaciones_leidas() from public;
grant execute on function public.marcar_notificaciones_leidas() to authenticated;

-- ── el apuntador ────────────────────────────────────────────────────────────
create or replace function public.anotar_aviso(
  p_tipo text, p_titulo text, p_detalle text,
  p_destinatario text, p_contrato uuid, p_enlace text)
returns void
language sql security definer set search_path = public as $$
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace)
  values (p_tipo, p_titulo, p_detalle, nullif(btrim(coalesce(p_destinatario,'')),''), p_contrato, p_enlace);
$$;
revoke execute on function public.anotar_aviso(text,text,text,text,uuid,text) from public, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- DISPARADORES
-- Ninguno puede tumbar la escritura que lo dispara: un aviso perdido es
-- molesto, un contrato que no se guarda no. Por eso todos van envueltos en su
-- bloque de excepción, igual que el alta de compradores. El fallo queda de
-- warning en el log de Postgres.
-- ═══════════════════════════════════════════════════════════════

-- 1 · CONTRATO FIRMADO — el aviso que pidió el owner con nombre y apellidos.
--     Se cuelga de `bloqueado`, no de `contrato_firmas`: bloqueado es lo que
--     significa «este documento ya está cerrado», y lo pone tanto la firma
--     remota como la subida manual del PDF. Colgarlo de la firma dejaría fuera
--     la mitad de los casos.
create or replace function public.trg_aviso_contrato_firmado()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if coalesce(new.bloqueado,false) and not coalesce(old.bloqueado,false) then
      perform anotar_aviso('contrato_firmado',
        coalesce(new.numero,'Contrato') || ' firmado',
        coalesce(new.comprador_nombre,'sin comprador')
          || coalesce(' · ' || new.proyecto_nombre, ''),
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

-- 2 · ENLACE DE FIRMA ENVIADO
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

-- 3 · FACTURA EMITIDA, y si con ella se salda la operación, también eso.
--     Las proformas no avisan: no son documento fiscal y no suman al cobrado
--     (misma regla que en Operaciones, para que las dos pantallas no digan
--     cosas distintas del mismo dinero).
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

-- 4 · INVENTARIO. Lo mueve solo el disparador que ya existe
--     (`sincroniza_unidad_contrato`, 31-jul), así que esto no añade ninguna
--     regla nueva: solo cuenta lo que aquel hace.
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
    if v_texto is null then return new; end if;   -- bloqueada/no_disponible las pone una persona

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
for each row execute function public.trg_aviso_unidad();

-- ═══════════════════════════════════════════════════════════════
-- SIEMBRA DE LO YA OCURRIDO
-- Para que la campana no nazca vacía. Con la fecha REAL de cada hecho, no con
-- la de hoy: un aviso de hace tres semanas fechado hoy es mentira.
-- Y a continuación se pone a todo el mundo el visto en `now()`, para que nadie
-- entre mañana con cuarenta avisos «nuevos» de cosas que ya sabe. La historia
-- queda ahí para consultarla; el contador arranca a cero.
-- ═══════════════════════════════════════════════════════════════
insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, creado_en)
select 'contrato_firmado',
       coalesce(c.numero,'Contrato') || ' firmado',
       coalesce(c.comprador_nombre,'sin comprador') || coalesce(' · ' || c.proyecto_nombre,''),
       c.creado_por, c.id, '/operaciones/?contrato=' || c.id,
       coalesce(c.fecha_firma::timestamptz, c.created_at)
  from public.contratos c
 where c.bloqueado
   and not exists (select 1 from public.notificaciones n
                    where n.contrato_id = c.id and n.tipo = 'contrato_firmado');

insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, creado_en)
select 'factura_emitida',
       'Factura ' || coalesce(f.numero,'sin nº') || ' emitida',
       coalesce(f.cliente_nombre,'') || ' · ' ||
         trim(to_char(coalesce(f.total,0),'FM999G999G990D00')) || ' ' || coalesce(f.moneda,''),
       coalesce(f.creado_por, c.creado_por), f.contrato_id,
       case when f.contrato_id is null then '/facturas/' else '/operaciones/?contrato=' || f.contrato_id end,
       f.created_at
  from public.facturas f
  left join public.contratos c on c.id = f.contrato_id
 where not coalesce(f.anulada,false) and f.tipo <> 'proforma'
   and not exists (select 1 from public.notificaciones n
                    where n.tipo = 'factura_emitida' and n.titulo like '%' || coalesce(f.numero,'∅') || '%');

update public.usuarios set notif_visto_hasta = now() where notif_visto_hasta is null;

-- ═══════════════════════════════════════════════════════════════
-- COMPROBACIÓN
-- ═══════════════════════════════════════════════════════════════
select tipo, count(*) as avisos,
       count(*) filter (where destinatario is null) as solo_admin
  from public.notificaciones group by tipo order by 2 desc;
