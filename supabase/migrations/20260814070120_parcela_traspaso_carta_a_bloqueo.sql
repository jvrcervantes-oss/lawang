create or replace function public.sincroniza_unidad_contrato()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  cod          text := nullif(btrim(new.datos->'fields'->>'parcela_codigo'), '');
  proy         text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  cod_ant      text;
  ocupada      text;
  ocupada_tipo text;
  traspaso_ok  boolean;
begin
  if tg_op = 'UPDATE' then
    cod_ant := nullif(btrim(old.datos->'fields'->>'parcela_codigo'), '');
    if cod_ant is distinct from cod then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id;
    end if;
  end if;

  if cod is null or proy is null then return new; end if;

  -- ahora importa QUIEN ocupa, no solo que haya alguien
  select c.numero, c.tipo into ocupada, ocupada_tipo
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;

  traspaso_ok := new.tipo = 'reserva_parcela'
             and ocupada_tipo in ('carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa');

  if ocupada is not null and not traspaso_ok then
    raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
      using errcode = '23505';
  end if;

  update public.unidades u
     set contrato_id = new.id,
         estado = case
           -- vendida/cobrada solo las mueve el dinero (avanza_unidad_por_cobro)
           --  ninguna firma ni edicion de contrato las revierte.
           when u.estado in ('vendida','cobrada') then u.estado
           when u.estado = 'no_disponible' then u.estado
           -- bloqueada manual (sin RP firmado detras): protegida, igual que siempre.
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
           -- Contrato de Construccion: no mueve el estado de la parcela.
           when new.tipo = 'construccion' then u.estado
           -- cualquier otro caso (crear CR/RP, o firmar una CR) se queda en reservada.
           else 'reservada'
         end
   where u.proyecto = proy and u.codigo = cod;

  return new;
end $$;;
