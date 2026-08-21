-- destructivo-ok: redefine el CASE del trigger existente (sincroniza_unidad_contrato) para que mire tipo de contrato ademas de bloqueado, corrigiendo el bug de que firmar una Carta de Reserva saltaba a 'vendida'. El unico DROP real es unidades_estado_check, sustituido en la misma sentencia para anadir el valor 'cobrada' -- ninguna fila se borra ni pierde su estado actual (el CASE nuevo empieza siempre protegiendo lo que ya habia). Los DROP TRIGGER IF EXISTS son el patron estandar de esta suite antes de un CREATE TRIGGER.

create or replace function public.sincroniza_unidad_contrato()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  cod     text := nullif(btrim(new.datos->'fields'->>'parcela_codigo'), '');
  proy    text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  cod_ant text;
  ocupada text;
begin
  if tg_op = 'UPDATE' then
    cod_ant := nullif(btrim(old.datos->'fields'->>'parcela_codigo'), '');
    if cod_ant is distinct from cod then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id;
    end if;
  end if;

  if cod is null or proy is null then return new; end if;

  select c.numero into ocupada
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;
  if ocupada is not null then
    raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
      using errcode = '23505';
  end if;

  update public.unidades u
     set contrato_id = new.id,
         estado = case
           when u.estado in ('vendida','cobrada') then u.estado
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
           when new.tipo = 'construccion' then u.estado
           else 'reservada'
         end
   where u.proyecto = proy and u.codigo = cod;

  return new;
end $$;

create or replace function public.avanza_unidad_por_cobro(p_contrato_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_cobrado numeric;
  v_mezcla  boolean;
begin
  if p_contrato_id is null then return; end if;

  select exists (
    select 1 from public.facturas f
     where f.contrato_id = p_contrato_id and f.tipo = 'recibi' and not coalesce(f.anulada, false)
       and f.moneda is distinct from (select u.moneda from public.unidades u where u.contrato_id = p_contrato_id)
  ) into v_mezcla;
  if v_mezcla then return; end if;

  v_cobrado := coalesce(public.contrato_cobrado(p_contrato_id), 0);

  update public.unidades u
     set estado = case
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when u.precio > 0 and v_cobrado >= u.precio then 'cobrada'
           when v_cobrado > 0 then 'vendida'
           else u.estado
         end
   where u.contrato_id = p_contrato_id;
end $$;

revoke all on function public.avanza_unidad_por_cobro(uuid) from public, anon, authenticated;

create or replace function public.trg_avanza_por_recibi()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tipo = 'recibi' then
    perform public.avanza_unidad_por_cobro(new.contrato_id);
  end if;
  return new;
end $$;

drop trigger if exists trg_avanza_por_recibi on public.facturas;
create trigger trg_avanza_por_recibi
  after insert or update of anulada, total, contrato_id, tipo on public.facturas
  for each row execute function public.trg_avanza_por_recibi();

create or replace function public.trg_avanza_por_aplicacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_contrato_id uuid;
begin
  select f.contrato_id into v_contrato_id from public.facturas f where f.id = new.factura_id;
  perform public.avanza_unidad_por_cobro(v_contrato_id);
  return new;
end $$;

drop trigger if exists trg_avanza_por_aplicacion on public.recibi_aplicaciones;
create trigger trg_avanza_por_aplicacion
  after insert on public.recibi_aplicaciones
  for each row execute function public.trg_avanza_por_aplicacion();

alter table public.unidades drop constraint unidades_estado_check;
alter table public.unidades add constraint unidades_estado_check
  check (estado = any (array['disponible','reservada','vendida','bloqueada','no_disponible','cobrada']));
;
