CREATE OR REPLACE FUNCTION public._trg_comisiones_reconcilia_contrato()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare v_raices uuid[]; v_r uuid; v_origen jsonb; v_on boolean;

begin

  v_on := coalesce((select i.recalculo_auto from public.comisiones_interruptor i where i.id), false);

  v_origen := jsonb_build_object(

    'tabla', 'contratos', 'op', tg_op, 'contrato_id', new.id, 'numero', new.numero, 'en', now(),

    'quien', auth.email(),

    'precio_total', jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.precio_total end, 'despues', new.precio_total),

    'firmado',      jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.bloqueado end,    'despues', new.bloqueado),

    'padre',        jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.contrato_padre_id end, 'despues', new.contrato_padre_id),

    'tipo',         jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.tipo end,         'despues', new.tipo),

    'liberado',     jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.liberado_en end,  'despues', new.liberado_en),

    'moneda',       jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.moneda end,       'despues', new.moneda));

  v_raices := array[new.id, coalesce(new.contrato_padre_id, new.id)];

  if tg_op = 'UPDATE' then

    v_raices := v_raices || coalesce(old.contrato_padre_id, old.id);

  end if;

  begin

    -- orden fijo: dos transacciones que tocan las mismas ventas toman los candados igual

    for v_r in select distinct u from unnest(v_raices) u where u is not null order by u loop

      if v_on then

        perform public.comisiones_reconciliar(v_r, false, v_origen);

      end if;

      -- evaluar NO depende del interruptor: con la base de solo firmados, un tramo que se

      -- cruzó antes de firmar (base 0) tiene que devengar al firmarse, no al siguiente cobro

      perform public.comisiones_evaluar_contrato(v_r);

    end loop;

  exception when others then

    -- una comisión nunca impide guardar un contrato: queda anotado para el vigilante

    update public.comisiones_interruptor

       set ultimo_error = sqlerrm || ' (contrato ' || coalesce(new.numero, new.id::text) || ')', ultimo_error_en = now()

     where id;

    raise warning 'recalculo de comisiones fallido para %: %', new.numero, sqlerrm;

  end;

  return null;

end $function$
