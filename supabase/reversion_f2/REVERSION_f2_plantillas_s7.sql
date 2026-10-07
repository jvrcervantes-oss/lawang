-- Reversion de la migracion 20261009010000 (S7 · pantalla «Textos de contrato», 8-oct-2026).
-- Quita las dos RPC nuevas (edicion, revisa) y _plantilla_sin_notas, devuelve _plantilla_exige_bloques a su definicion de 20261008990100 (la que compara contra el esqueleto CON notas)
-- y deja las 5 RPC de S2 que la pantalla llamaba otra vez sin EXECUTE para authenticated (estado de 20261009000000). No toca filas.
-- OJO: tras revertir, una empresa vuelve a NO poder guardar un borrador de las 9 plantillas cuya semilla lleva notas dentro de un bloque fijo (ver el hallazgo en la cabecera de la migracion).
-- destructivo-ok: retira tres funciones creadas por la migracion que se revierte y restituye la anterior; sin datos
begin;
revoke execute on function public.plantilla_contrato_versiones_lista(text, text), public.plantilla_contrato_cuerpo_version(uuid, text),
  public.plantilla_contrato_guarda_borrador(text, text, text, text), public.plantilla_contrato_activa(uuid, text, boolean), public.plantilla_contrato_descarta_borrador(uuid) from authenticated;
drop function public.plantilla_contrato_edicion(text, text);
drop function public.plantilla_contrato_revisa(text, text, text);
create or replace function public._plantilla_exige_bloques(p_cuerpo text, p_esqueleto text, p_empresa text, p_slug text) returns void
language plpgsql stable security definer set search_path = '' as $f$
declare a text[]; b text[]; sg text;
begin
  if public.es_super_admin() then return; end if;               -- el super GLOBAL (con su abogado) si puede
  if p_esqueleto is null then return; end if;                    -- sin esqueleto el validador de S3 ya rechaza
  select s.motivo into sg from public.plantilla_solo_global s where s.slug = p_slug;
  if sg is not null then
    if public._plantilla_ws(p_cuerpo) is distinct from public._plantilla_ws(p_esqueleto) then
      raise exception '%', 'Este texto no lo cambia una empresa sola. ' || sg using errcode = '42501';
    end if;
    return;
  end if;
  a := public._plantilla_bloques_fijos(p_cuerpo, p_slug);
  b := public._plantilla_bloques_fijos(p_esqueleto, p_slug);
  if a is distinct from b then
    raise exception 'Tu texto cambia un bloque que una empresa no edita sola (foro y ley aplicable, tenencia, escrow e impuestos, prorroga, defectos, datos, partes y firmas, clausulas negociadas) o anade en un parrafo libre palabras de esos temas. Esos bloques los cambia el administrador global con su abogado: bloques fijos %, recibidos %', cardinality(b), cardinality(a) using errcode = '42501';
  end if;
end $f$;

drop function public._plantilla_sin_notas(text);
revoke all on function public._plantilla_exige_bloques(text, text, text, text) from public, anon, authenticated, service_role;
commit;
