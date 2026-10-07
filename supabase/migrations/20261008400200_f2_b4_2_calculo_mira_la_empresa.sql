-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 4 · migracion 2 (8-oct-2026): LA ELECCION DE EQUIPO Y DE CONDICION ESTANDAR MIRA LA EMPRESA DEL PROYECTO DE LA VENTA.
--   Con equipos y condiciones duplicados por empresa (migracion 1) hay que decir a cual se refiere cada venta. Sin esto, «el miembro mas reciente» elegiria
--   el gemelo de la otra empresa. Reglas:
--   * VENTA YA CONGELADA (contrato_closer.equipo_id): manda su equipo congelado, sea de la empresa que sea. NO se toca (ni sus condiciones fijas por devengo).
--   * VENTA SIN CONGELAR: el equipo se busca solo entre los de la empresa del proyecto. Proyecto sin empresa (Karana) = sin equipo y sin condicion estandar (nace cerrado).
--   * CONDICION ESTANDAR (sin equipo): solo las de la empresa del proyecto.
--   Medido antes de escribir esto (8-oct): las 86 ventas sin congelar NO resuelven a ningun equipo hoy, asi que ninguna cambia de equipo; las condiciones estandar
--   de sandal_woods son copia exacta (valores y tramos) de las de lawang. La prueba compara, venta a venta, lo que devengaria el motor antes y despues.
--   Tambien: mi_condicion_comision recorre TODOS los equipos vigentes de la persona (ahora puede estar en uno por empresa) y devuelve la empresa;
--   _condicion_solapa no cruza empresas; _condicion_ventas_afectadas gana el parametro empresa (la version de 6 argumentos se retira en la migracion 4).
-- destructivo-ok: create or replace de 6 funciones por parche con marca (cada marca debe salir las veces esperadas o aborta), una funcion nueva y drop+create de mi_condicion_comision (misma firma + 1 columna); sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b4.sql

create or replace function pg_temp.parchea(p_sig regprocedure, p_pares text[]) returns void language plpgsql as $f$
declare d text; i int := 1; v_old text; v_new text; v_n int; v_esp int;
begin
  d := pg_get_functiondef(p_sig);
  while i <= array_length(p_pares, 1) loop
    v_old := p_pares[i]; v_new := p_pares[i + 1]; v_esp := p_pares[i + 2]::int;
    v_n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
    if v_n <> v_esp then
      raise exception 'parchea %: la marca «%» sale % veces y se esperaban % (la funcion viva no es la que se leyo)', p_sig, left(v_old, 90), v_n, v_esp;
    end if;
    d := replace(d, v_old, v_new);
    i := i + 3;
  end loop;
  execute d;
end $f$;

-- ---------------------------------------------------------------- equipo de una venta: solo equipos de la empresa del proyecto
select pg_temp.parchea('public._equipo_de_venta(uuid)'::regprocedure, array[
  $o$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo$o$,
  $n$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo and ev.empresa = public._empresa_de_contrato_int(p_raiz)$n$, '1']);
select pg_temp.parchea('public._venta_equipo(uuid)'::regprocedure, array[
  $o$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo$o$,
  $n$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo and ev.empresa = public._empresa_de_contrato_int(p_contrato)$n$, '1']);
select pg_temp.parchea('public._venta_congela_equipo(uuid)'::regprocedure, array[
  $o$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo$o$,
  $n$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo and ev.empresa = public._empresa_de_contrato_int(p_raiz)$n$, '1']);

-- ---------------------------------------------------------------- el motor: equipo y condicion estandar de la empresa del proyecto
select pg_temp.parchea('public.comisiones_evaluar_contrato(uuid)'::regprocedure, array[
  $o$v_man_base             text;$o$,
  $n$v_man_base             text;
  v_empresa              text;$n$, '1',
  $o$v_precio_total := public._comisiones_precio_total(v_raiz_id);$o$,
  $n$v_precio_total := public._comisiones_precio_total(v_raiz_id);
  v_empresa := public._empresa_de_proyecto_int(v_proyecto_id);$n$, '1',
  $o$where lower(em.closer_email) = lower(v_closer_email)$o$,
  $n$where lower(em.closer_email) = lower(v_closer_email)
     and ev.empresa = v_empresa$n$, '1',
  $o$where c.equipo_id is null$o$,
  $n$where c.equipo_id is null
         and c.empresa = v_empresa$n$, '1']);

-- ---------------------------------------------------------------- lista de ventas con equipo: equipo de la empresa de la venta; «administrador» = el de ESA empresa
select pg_temp.parchea('public.comisiones_ventas_equipo()'::regprocedure, array[
  $o$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo$o$,
  $n$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo and ev.empresa = public._empresa_de_contrato_int(c.id)$n$, '1',
  $o$(yo.admin or lower(ev.manager_email) = yo.e or v.closer = yo.e$o$,
  $n$(public.puede_reparto_de(public._empresa_de_contrato_int(v.id)) or lower(ev.manager_email) = yo.e or v.closer = yo.e$n$, '1']);

-- ---------------------------------------------------------------- no cruzar empresas al detectar solapes
select pg_temp.parchea('public._condicion_solapa(uuid)'::regprocedure, array[
  $o$and b.nivel = a.nivel$o$,
  $n$and b.nivel = a.nivel
     and b.empresa = a.empresa$n$, '1']);

-- ---------------------------------------------------------------- recuento de ventas afectadas: con empresa (nueva sobrecarga de 7 argumentos, SIN default: la de 6 sigue hasta la migracion 4)
select pg_temp.parchea('public._condicion_ventas_afectadas(uuid,uuid,text,text,date,date)'::regprocedure, array[
  $o$CREATE OR REPLACE FUNCTION public._condicion_ventas_afectadas(p_equipo uuid, p_proy uuid, p_nivel text, p_closer text, p_d1 date, p_d2 date)$o$,
  $n$CREATE OR REPLACE FUNCTION public._condicion_ventas_afectadas(p_equipo uuid, p_proy uuid, p_nivel text, p_closer text, p_d1 date, p_d2 date, p_empresa text)$n$, '1',
  $o$and (p_proy is null or c.proyecto_id = p_proy)$o$,
  $n$and (p_proy is null or c.proyecto_id = p_proy)
     and public._empresa_de_contrato_int(c.id) = p_empresa$n$, '1']);
revoke all on function public._condicion_ventas_afectadas(uuid, uuid, text, text, date, date, text) from public, anon, authenticated, lw_lector;

-- ---------------------------------------------------------------- «Mi condicion»: todos mis equipos vigentes (uno por empresa) y la empresa de cada fila
drop function public.mi_condicion_comision();
create function public.mi_condicion_comision()
 returns table(ambito text, equipo_nombre text, oculta boolean, proyecto_id uuid, nivel text, pct_comision numeric, base_calculo text, importe_fijo numeric, personal boolean, vigente_desde date, empresa text)
 language plpgsql stable security definer set search_path = '' as $$
declare
  v_yo text := lower(coalesce(auth.email(), ''));
  v_hoy date := current_date;
  v_eq record;
  v_nivel text;
  v_p uuid;
  v_emp text;
  v_c public.condiciones_comision;
  v_vistas uuid[] := '{}';
  v_claves text[] := '{}';
  v_k text;
  v_hay boolean := false;
begin
  if auth.uid() is null or v_yo = '' then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;

  -- sus equipos HOY (el mismo criterio de membresia que la pantalla); una persona puede estar en uno por empresa
  for v_eq in
    select em.equipo_id, em.rol, ev.nombre, ev.closers_ven_comision, ev.empresa
      from public.equipo_miembros em
      join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
     where lower(em.closer_email) = v_yo and em.desde <= v_hoy and (em.hasta is null or em.hasta >= v_hoy)
     order by em.created_at desc
  loop
    v_hay := true;
    if not coalesce(v_eq.closers_ven_comision, true) then
      v_k := md5(concat_ws('|', 'equipo', v_eq.nombre, 'oculta'));
      if not (v_k = any (v_claves)) then
        v_claves := v_claves || v_k;
        return query select 'equipo'::text, v_eq.nombre::text, true, null::uuid, null::text, null::numeric, null::text,
                            null::numeric, null::boolean, null::date, v_eq.empresa::text;
      end if;
      continue;
    end if;
    v_nivel := case when v_eq.rol in ('closer', 'setter', 'team_lead') then v_eq.rol else 'closer' end;
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id and c.nivel = v_nivel and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      -- mismo filtro y orden que comisiones_evaluar_contrato: la personal manda; si no, la generica del equipo
      select * into v_c from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id
         and (c.proyecto_id = v_p or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and lower(c.closer_email) = v_yo
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
      if not found then
        select * into v_c from public.condiciones_comision c
         where c.equipo_id = v_eq.equipo_id
           and (c.proyecto_id = v_p or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;
      if found and not (v_c.id = any (v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        -- dos equipos gemelos con las mismas cifras se muestran una sola vez; si un dia difieren, salen los dos con su empresa
        v_k := md5(concat_ws('|', 'equipo', v_eq.nombre, v_c.proyecto_id, v_c.nivel, v_c.pct_comision, v_c.base_calculo, v_c.importe_fijo,
                             v_c.closer_email is not null, v_c.vigente_desde));
        if not (v_k = any (v_claves)) then
          v_claves := v_claves || v_k;
          return query select 'equipo'::text, v_eq.nombre::text, false, v_c.proyecto_id, v_c.nivel, v_c.pct_comision,
                              v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde, v_eq.empresa::text;
        end if;
      end if;
    end loop;
  end loop;
  if v_hay then return; end if;

  -- sin equipo: la estandar vigente de cada empresa en la que puede vender (mismo filtro y orden que el nivel 'estandar' del motor)
  for v_emp in select e.clave from public.empresas e where e.activa and public.puede_empresa(e.clave) order by e.orden loop
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.empresa = v_emp and c.equipo_id is null and c.nivel = 'closer' and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      select * into v_c from public.condiciones_comision c
       where c.empresa = v_emp
         and c.equipo_id is null
         and c.nivel = 'closer'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.proyecto_id = v_p or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
      if found and not (v_c.id = any (v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        v_k := md5(concat_ws('|', 'estandar', v_c.proyecto_id, v_c.pct_comision, v_c.base_calculo, v_c.importe_fijo,
                             v_c.closer_email is not null, v_c.vigente_desde));
        if not (v_k = any (v_claves)) then
          v_claves := v_claves || v_k;
          return query select 'estandar'::text, null::text, false, v_c.proyecto_id, 'estandar'::text, v_c.pct_comision,
                              v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde, v_emp::text;
        end if;
      end if;
    end loop;
  end loop;
end $$;
revoke all on function public.mi_condicion_comision() from public, anon;
grant execute on function public.mi_condicion_comision() to authenticated;
