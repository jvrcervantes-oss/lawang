-- Creatividades v4, rediseño A «mesa de trabajo» (owner 24-sep-2026: «elige tú»).
-- Estado nuevo `pendiente` = «para aprobar». Quien hace la pieza la ENVÍA; un admin
-- con la casilla del tipo la aprueba o la devuelve a borrador. Antes solo había
-- borrador → aprobada y el admin no tenía forma de saber qué estaba listo para mirar:
-- en la biblioteca todo borrador parecía igual de terminado.
--
-- `pendiente` queda CONGELADO como cualquier estado que no es borrador (el trigger
-- `_creatividades_antes` ya lo hace: `old.estado <> 'borrador'`): lo que se aprueba es
-- exactamente lo que se envió. Lo ven solo quienes tienen la casilla de hacerlo
-- (`creatividad_puede_ver` no cambia: los comerciales siguen viendo solo aprobada y
-- publicada).
-- destructivo-ok: se reemplaza un CHECK por otro MÁS AMPLIO (añade 'pendiente'); no se borra ningún dato ni columna
alter table public.creatividades drop constraint creatividades_estado_check;
alter table public.creatividades add constraint creatividades_estado_check
  check (estado in ('borrador','pendiente','aprobada','publicada','archivada'));
alter table public.creatividades add column enviada_por uuid, add column enviada_en timestamptz;

create index if not exists creatividades_pendientes_idx on public.creatividades (tipo) where estado = 'pendiente';

create or replace function public.creatividad_estado(p_id uuid, p_estado text)
returns public.creatividades language plpgsql security definer set search_path = '' as $$
declare c public.creatividades; v_admin boolean;
begin
  select * into c from public.creatividades where id = p_id for update;
  if not found then raise exception 'No existe esa creatividad.' using errcode = 'P0002'; end if;
  if not public.creatividad_puede_hacer(c.tipo) then
    raise exception 'Hace falta la casilla de % para cambiar el estado.',
      case c.tipo when 'pieza' then 'Creatividades' else 'Dossier' end using errcode = '42501';
  end if;
  v_admin := public.es_admin();
  -- Enviar a aprobar y retirar el envío: quien tenga la casilla del tipo.
  -- Todo lo demás (aprobar, devolver, publicar, archivar): solo un admin con la casilla.
  if not ((c.estado = 'borrador'  and p_estado = 'pendiente')
       or (c.estado = 'pendiente' and p_estado = 'borrador')
       or (v_admin and (
              (c.estado = 'borrador'  and p_estado in ('aprobada','archivada'))
           or (c.estado = 'pendiente' and p_estado in ('aprobada','archivada'))
           or (c.estado = 'aprobada'  and p_estado in ('publicada','archivada'))
           or (c.estado = 'publicada' and p_estado = 'archivada')))) then
    if not v_admin and p_estado in ('aprobada','publicada','archivada') then
      raise exception 'Solo un admin con la casilla de % aprueba, publica o archiva.',
        case c.tipo when 'pieza' then 'Creatividades' else 'Dossier' end using errcode = '42501';
    end if;
    raise exception 'No se pasa de «%» a «%».', c.estado, p_estado using errcode = '23514';
  end if;
  if p_estado in ('pendiente','aprobada') then
    if c.estado_path is null or (c.tipo = 'pieza' and c.path is null) then
      raise exception 'Guarda la creatividad antes: falta el fichero.' using errcode = '23514';
    end if;
  end if;
  update public.creatividades set
    estado = p_estado,
    enviada_por  = case when p_estado = 'pendiente' then (select auth.uid())
                        when p_estado = 'borrador'  then null else enviada_por end,
    enviada_en   = case when p_estado = 'pendiente' then now()
                        when p_estado = 'borrador'  then null else enviada_en end,
    aprobada_por = case when p_estado = 'aprobada' then (select auth.uid()) else aprobada_por end,
    aprobada_en  = case when p_estado = 'aprobada' then now() else aprobada_en end,
    publicada_en = case when p_estado = 'publicada' then now() else publicada_en end,
    archivada_en = case when p_estado = 'archivada' then now() else archivada_en end
  where id = p_id returning * into c;
  return c;
end $$;
revoke all on function public.creatividad_estado(uuid, text) from public, anon;
grant execute on function public.creatividad_estado(uuid, text) to authenticated;

-- El trigger de inserción ya pone a null lo de aprobación; lo de envío, igual.
create or replace function public._creatividades_antes()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if old.estado <> 'borrador' and (
         new.path is distinct from old.path or new.estado_path is distinct from old.estado_path
      or new.titulo is distinct from old.titulo or new.proyecto_id is distinct from old.proyecto_id
      or new.formato is distinct from old.formato or new.arquetipo is distinct from old.arquetipo
      or new.precios_a is distinct from old.precios_a or new.tipo is distinct from old.tipo) then
      raise exception 'Solo se edita un borrador. Para cambiar esta creatividad, haz una copia.' using errcode = '23514';
    end if;
    new.tipo := old.tipo;
    new.origen := old.origen;
    new.creado_por := old.creado_por;
    new.creado_en  := old.creado_en;
    new.actualizado_por := (select auth.uid());
    new.actualizado_en  := now();
  else
    new.creado_por := coalesce((select auth.uid()), new.creado_por);
    new.creado_en  := now();
    new.actualizado_por := null; new.actualizado_en := null;
    new.aprobada_por := null; new.aprobada_en := null;
    new.enviada_por := null; new.enviada_en := null;
    new.publicada_en := null; new.archivada_en := null;
    new.lleva_render := false;
    if (select auth.uid()) is not null then new.estado := 'borrador'; new.origen := null; end if;
  end if;
  return new;
end $$;
revoke all on function public._creatividades_antes() from public, anon, authenticated;
