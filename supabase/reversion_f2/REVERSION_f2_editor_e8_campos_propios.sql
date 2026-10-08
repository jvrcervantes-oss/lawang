-- Reversion de la migracion 20261010010000 (E8 · catalogo de campos propios por empresa, 8-oct-2026).
-- Quita el trigger de valores en contratos, las 6 RPC, el catalogo y sus ayudantes, y devuelve a su forma anterior las 4 funciones del validador (_plantilla_texto, _plantilla_valida,
-- plantilla_contrato_revisa, _plantilla_exige_valido) y su volatilidad (immutable).
-- GUARDA: aborta si el catalogo tiene filas o si algun contrato guarda un valor cx_*; con datos, la reversion los dejaria huerfanos. Archiva los campos y limpia los valores antes, a mano.
-- destructivo-ok: elimina la tabla plantilla_campos_propios y funciones creadas por E8, VACIA (la guarda aborta si tiene filas) y sin ningun valor cx_ en contratos; no toca filas de otras tablas
begin;

do $g$
declare n int; m int;
begin
  select count(*) into n from public.plantilla_campos_propios;
  select count(*) into m from public.contratos where datos_fields::text like '%"cx\_%';
  if n > 0 or m > 0 then
    raise exception 'REVERSION ABORTADA: hay % campo(s) propio(s) en el catalogo y % contrato(s) con valores cx_. Vacialos antes.', n, m using errcode = '55000';
  end if;
end $g$;

drop trigger if exists trg_contrato_campos_propios on public.contratos;
drop function if exists public._trg_contrato_campos_propios();

drop function if exists public.plantilla_campo_propio_guarda(text, text, text, text, text, text, jsonb, boolean, boolean);
drop function if exists public.plantilla_campo_propio_archiva(text, text, boolean);
drop function if exists public.plantilla_campo_propio_borra(text, text);
drop function if exists public.plantilla_campo_propio_lista(text, boolean);
drop function if exists public.plantilla_campo_propio_valida(text, jsonb);
drop function if exists public.plantilla_campos_cx_publicos(text, uuid);

-- 1. _plantilla_exige_valido como era (S2.2)
create or replace function public._plantilla_exige_valido(p_cuerpo text, p_empresa text, p_slug text) returns void
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if pg_catalog.to_regprocedure('public.plantilla_cuerpo_valida(text,text)') is null then
    raise exception 'El validador de plantillas no esta instalado: no se guarda ni se activa nada' using errcode = '55000';
  end if;
  execute 'select public.plantilla_cuerpo_valida($1, $2)' into r using p_cuerpo, public._plantilla_esqueleto(p_empresa, p_slug);
  if r is null or coalesce((r ->> 'ok')::boolean, false) is not true then
    raise exception 'El texto no pasa la validacion: %', coalesce(left((select string_agg(e, ' | ') from (select jsonb_array_elements_text(r -> 'errores') e limit 5) q), 600), 'sin detalle') using errcode = '22023';
  end if;
end $$;
revoke all on function public._plantilla_exige_valido(text, text, text) from public, anon, authenticated, service_role;

-- 2. las otras tres, quitando lo que E8 anadio
do $p$
declare d text; d2 text;
begin
  d := pg_get_functiondef('public._plantilla_texto(text,boolean)'::regprocedure);
  d2 := replace(d,
$r$elsif mk ~ '^cx_' then
          if mk !~ '^cx_[a-z0-9_]{1,40}$' then
            e := e || ('campo propio con forma no permitida {{' || left(mk, 40) || '}} (cx_ y hasta 40 letras minusculas, cifras o guion bajo)');
          elsif coalesce(pg_catalog.current_setting('lw.cx_abierto', true), '') <> '1'
                and not (mk = any (pg_catalog.string_to_array(coalesce(pg_catalog.current_setting('lw.cx_catalogo', true), ''), ','))) then
            e := e || ('campo propio {{' || mk || '}} no esta en el catalogo de campos de esta empresa, o esta archivado');
          end if;
        elsif not (mk = any (public._plantilla_marcadores())) then$r$, 'elsif not (mk = any (public._plantilla_marcadores())) then');
  if d2 = d and d like '%lw.cx_catalogo%' then raise exception 'reversion E8: no encuentro la rama cx_ en _plantilla_texto'; end if;
  if d2 <> d then execute d2; end if;

  d := pg_get_functiondef('public._plantilla_valida(text,text,boolean)'::regprocedure);
  d2 := replace(d,
$r$perform pg_catalog.set_config('lw.cx_abierto', '1', true);
    b := public._plantilla_analiza(p_esqueleto, true);
    perform pg_catalog.set_config('lw.cx_abierto', '', true);$r$, 'b := public._plantilla_analiza(p_esqueleto, true);');
  if d2 = d and d like '%lw.cx_abierto%' then raise exception 'reversion E8: no encuentro el modo abierto en _plantilla_valida'; end if;
  if d2 <> d then execute d2; end if;

  d := pg_get_functiondef('public.plantilla_contrato_revisa(text,text,text)'::regprocedure);
  d2 := replace(d,
$r$perform public._plantilla_cx_contexto(p_empresa, false);
  r := public._plantilla_valida(p_cuerpo, v_esq, false);
  perform pg_catalog.set_config('lw.cx_catalogo', '', true);$r$, 'r := public._plantilla_valida(p_cuerpo, v_esq, false);');
  if d2 = d and d like '%_plantilla_cx_contexto%' then raise exception 'reversion E8: no encuentro el contexto en plantilla_contrato_revisa'; end if;
  if d2 <> d then execute d2; end if;
end $p$;

alter function public._plantilla_texto(text, boolean) immutable;
alter function public._plantilla_analiza(text, boolean) immutable;
alter function public._plantilla_valida(text, text, boolean) immutable;
alter function public.plantilla_cuerpo_valida(text, text) immutable;
alter function public.plantilla_cuerpo_valida_semilla(text, text) immutable;
alter function public._plantilla_valida(text, text, boolean) parallel safe;
alter function public.plantilla_cuerpo_valida(text, text) parallel safe;
alter function public.plantilla_cuerpo_valida_semilla(text, text) parallel safe;

drop function if exists public._plantilla_cx_contexto(text, boolean);

-- 3. tabla y ayudantes
drop table if exists public.plantilla_campos_propios;
drop function if exists public._trg_cx_campo_ins();
drop function if exists public._trg_cx_campo_upd();
drop function if exists public._trg_cx_campo_del();
drop function if exists public._cx_en_uso(text, text);
drop function if exists public._cx_autoriza(text, boolean);
drop function if exists public._cx_valor(text, jsonb, jsonb);
drop function if exists public._cx_opciones_ok(jsonb);

commit;
