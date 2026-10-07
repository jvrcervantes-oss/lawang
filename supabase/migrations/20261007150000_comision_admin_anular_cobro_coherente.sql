-- Anular un cobro no puede dejar líneas cobradas sin dinero detrás (revisor de código, 7-oct-2026).
-- Ejemplo: el cobro A (100) salda 80 y deja 20 de saldo; el cobro B (30) salda 50 usando esos 20. Anular A dejaría
-- las líneas de B «cobradas» sin dinero: el saldo sería −20 (registrar_cobro lo muestra como 0 a propósito).
-- Ahora anular_cobro comprueba el saldo de esa sociedad y moneda DESPUÉS de anular y, si sale negativo, se
-- niega y no cambia nada: hay que anular antes los cobros posteriores.
-- Además: mismo orden de bloqueo que registrar_cobro (líneas, luego cobros) y las líneas ya anuladas no
-- cambian de estado (solo sueltan el cobro_id).
create or replace function public.comision_admin_anular_cobro(p_cobro_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c public.comision_admin_cobros%rowtype;
  r record;
  v_prev text;
  v_n integer := 0;
  v_saldo numeric;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if not public.es_super_admin() then raise exception 'Solo un super admin' using errcode = '42501'; end if;
  if v_motivo is null or length(v_motivo) < 5 then
    raise exception 'Anular un cobro necesita un motivo (queda registrado)' using errcode = '22023';
  end if;
  select * into c from public.comision_admin_cobros where id = p_cobro_id;
  if not found then raise exception 'Ese cobro no existe' using errcode = 'P0002'; end if;
  -- mismo orden que registrar_cobro: primero las líneas de la sociedad, luego sus cobros
  perform 1 from public.comision_admin_lineas l
   where l.sociedad = c.sociedad and upper(l.moneda) = upper(c.moneda) order by l.id for update;
  perform 1 from public.comision_admin_cobros x
   where x.sociedad = c.sociedad and upper(x.moneda) = upper(c.moneda) order by x.id for update;
  select * into c from public.comision_admin_cobros where id = p_cobro_id;
  if c.anulado then
    return jsonb_build_object('ok', false, 'motivo', 'Ese cobro ya estaba anulado.');
  end if;
  for r in select l.id, l.estado, l.anulada from public.comision_admin_lineas l where l.cobro_id = p_cobro_id loop
    if r.anulada then
      update public.comision_admin_lineas set cobro_id = null, actualizado_en = now() where id = r.id;
    else
      select lg.estado_antes into v_prev from public.comision_admin_lineas_log lg
       where lg.linea_id = r.id and lg.estado_despues = 'cobrada' and lg.motivo like '%[lote ' || c.lote || ']%'
       order by lg.en desc limit 1;
      v_prev := coalesce(v_prev, 'pendiente');
      insert into public.comision_admin_lineas_log (linea_id, estado_antes, estado_despues, motivo)
      values (r.id, r.estado, v_prev, 'Cobro anulado [lote ' || c.lote || ']: ' || v_motivo);
      update public.comision_admin_lineas set estado = v_prev, cobro_id = null, actualizado_en = now() where id = r.id;
    end if;
    v_n := v_n + 1;
  end loop;
  update public.comision_admin_cobros
     set anulado = true, anulado_motivo = v_motivo, anulado_en = now(), anulado_por = auth.email()
   where id = p_cobro_id;

  v_saldo := coalesce((select sum(x.importe) from public.comision_admin_cobros x
                        where x.sociedad = c.sociedad and upper(x.moneda) = upper(c.moneda) and not x.anulado), 0)
           - coalesce((select sum(l.importe) from public.comision_admin_lineas l
                        where l.cobro_id in (select x.id from public.comision_admin_cobros x
                                              where x.sociedad = c.sociedad and upper(x.moneda) = upper(c.moneda)
                                                and not x.anulado)), 0);
  if round(v_saldo, case when upper(c.moneda) = 'IDR' then 0 else 2 end) < 0 then
    raise exception 'No se puede anular: cobros posteriores ya usaron ese dinero para saldar líneas (el saldo quedaría en %). Anula antes los cobros posteriores de esa sociedad.', round(v_saldo, 2)
      using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true, 'lineas_sueltas', v_n, 'importe', c.importe, 'moneda', c.moneda);
end $$;
