-- Reversion de S2 «plantillas de contrato por empresa» (migraciones 20261008980000..980300, 7-oct-2026).
-- Quita las 9 funciones y las 3 tablas nuevas. No toca `contratos` ni `plantillas_contrato`. Aborta si ya hay versiones activadas o retiradas (historia que no se tira sin decision del owner).
-- Las semillas (S4) y los vinculos sin activar se pierden: el texto sigue en los ficheros contracts/templates/.
-- destructivo-ok: retira objetos creados por S2; sin datos reales de contratos
begin;
do $$ begin
  if exists (select 1 from public.plantilla_contrato_versiones where estado in ('activa', 'retirada')) then
    raise exception 'Hay versiones activadas o retiradas: no se revierte sin decision del owner';
  end if;
end $$;
drop function if exists public.plantilla_contrato_fija(uuid, uuid);
drop function if exists public.plantilla_contrato_versiones_lista(text, text);
drop function if exists public.plantilla_contrato_version_de_contrato(uuid);
drop function if exists public.plantilla_contrato_cuerpo_version(uuid, text);
drop function if exists public.plantilla_contrato_cuerpo(text, uuid, text);
drop function if exists public.plantilla_contrato_descarta_borrador(uuid);
drop function if exists public.plantilla_contrato_activa(uuid, text, boolean);
drop function if exists public.plantilla_contrato_guarda_borrador(text, text, text, text);
drop function if exists public._plantilla_valida(text, text, text);
drop function if exists public._plantilla_esqueleto(text, text);
drop table if exists public.contrato_plantilla_version;
drop table if exists public.plantilla_contrato_cuerpos;
drop table if exists public.plantilla_contrato_versiones;
drop function if exists public._trg_contrato_plantilla_version();
drop function if exists public._trg_plantilla_cuerpo_iu();
drop function if exists public._trg_plantilla_sin_borrado();
drop function if exists public._trg_plantilla_version_upd();
drop function if exists public._trg_plantilla_version_ins();
drop function if exists public._plantilla_hash(text);
commit;
