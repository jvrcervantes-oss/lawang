-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 4 · migracion 2b (8-oct-2026): dos retoques que cazo la foto de no-regresion tras la migracion 2.
--   * comisiones_ventas_equipo: una venta de un proyecto SIN empresa (CH00001, la carta de reserva sin proyecto) dejo de salir en la lista de los administradores
--     (sin empresa no hay «equipo de su empresa»). Se lista, como siempre, con el equipo de lawang. Solo es la lista: el motor sigue sin equipo para ventas sin empresa.
--   * mi_condicion_comision: una ficha INACTIVA o sin alcance (martaruiz) no cuenta como «puede vender en una empresa» y se quedaba sin filas. Sin alcance restringido = todas las empresas, como antes.
--   Comprobado: la lista de ventas del equipo de cada una de las 34 fichas (por nombre de equipo, los gemelos se llaman igual) coincide con la de la funcion de antes.
-- destructivo-ok: create or replace de dos funciones por parche con marca; sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b4.sql

create or replace function pg_temp.parchea(p_sig regprocedure, p_pares text[]) returns void language plpgsql as $f$
declare d text; i int := 1; v_old text; v_new text; v_n int; v_esp int;
begin
  d := pg_get_functiondef(p_sig);
  while i <= array_length(p_pares, 1) loop
    v_old := p_pares[i]; v_new := p_pares[i + 1]; v_esp := p_pares[i + 2]::int;
    v_n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
    if v_n <> v_esp then
      raise exception 'parchea %: la marca «%» sale % veces y se esperaban %', p_sig, left(v_old, 90), v_n, v_esp;
    end if;
    d := replace(d, v_old, v_new);
    i := i + 3;
  end loop;
  execute d;
end $f$;

select pg_temp.parchea('public.comisiones_ventas_equipo()'::regprocedure, array[
  $o$ev.empresa = public._empresa_de_contrato_int(c.id)$o$,
  $n$ev.empresa = coalesce(public._empresa_de_contrato_int(c.id), 'lawang')$n$, '1']);
select pg_temp.parchea('public.mi_condicion_comision()'::regprocedure, array[
  $o$e.activa and public.puede_empresa(e.clave)$o$,
  $n$e.activa and (not public.alcance_restringido() or public.puede_empresa(e.clave))$n$, '1']);
