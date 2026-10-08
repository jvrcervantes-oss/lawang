-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · Sandal Woods · 5 borradores v2 con la sociedad firmante por marcador (8-oct-2026).
-- ORDEN DEL OWNER (8-oct-2026): «en Lawang deja todo como esta. En Sandal Woods haz los 5 contratos numerados solamente y adaptamos a PT Sandal Woods»
-- (carta_reserva, ppjb_reserva, ppjb_parcela, ppjb_construccion, poa_notario). Sobre REV04 dijo que el candado es solo de administrador (no de «nunca activar»):
--   se quita SOLO plantilla_nunca_activable de ppjb_parcela y ppjb_construccion PARA sandal_woods; plantilla_solo_global se queda (edita y activa solo el administrador global).
--   Lawang no se toca: ni sus filas de nunca_activable, ni versiones, ni vinculos.
-- QUE HACE: crea UNA version v2 (estado borrador, origen 'empresa', hereda_de la semilla v1 de SW) por plantilla = la semilla sin notas de autor y con el unico dato de
--   otra sociedad (« — LAWANG</title>») cambiado por el marcador {{prom_marca}} (la marca de la sociedad de la empresa; el resto de la sociedad ya salia por {{prom_*}} y la firma ya es por
--   `if:sociedad_firmante=`). Pasa por la misma validacion que plantilla_contrato_guarda_borrador (esqueleto, bloques fijos, otra sociedad, notas) SIN aflojar nada; para las
--   solo-global (ppjb_parcela, ppjb_construccion, poa_notario) se sigue la ruta del super global de _plantilla_exige_bloques y se exige que lo UNICO que cambia sea el titulo.
--   NO activa nada (activar lo hace el super admin desde «Textos de contrato», con su nombre y confirmacion).
-- destructivo-ok: borra 2 filas de plantilla_nunca_activable (empresa sandal_woods, orden del owner 8-oct); inserta 5 versiones y 5 cuerpos; idempotente (si ya hay version 'empresa' de esa plantilla, no hace nada)
-- REVERTIR:
--   update public.plantilla_contrato_versiones set estado='retirada', retirada_por='estudio', retirada_en=now() where empresa='sandal_woods' and origen='empresa' and autor='estudio (orden del owner 8-oct-2026)' and estado='borrador';
--   insert into public.plantilla_nunca_activable (empresa, slug, motivo) select 'sandal_woods', s, 'Lleva cláusulas REV04: pendiente de reclasificar por Legal; solo el administrador global con su abogado (se quita al reclasificar)' from unnest(array['ppjb_parcela','ppjb_construccion']) s on conflict do nothing;

delete from public.plantilla_nunca_activable
 where empresa = 'sandal_woods' and slug in ('ppjb_parcela', 'ppjb_construccion');

do $mig$
declare
  r record; v_seed public.plantilla_contrato_versiones%rowtype;
  v_cuerpo0 text; v_esq text; v_body text; v_id uuid; v_hash text; v_bytes int; v_idiomas text[]; v_bloq text; v_n int;
  c_viejo constant text := ' — LAWANG</title>';
  c_nuevo constant text := ' — {{prom_marca}}</title>';
begin
  for r in select s as slug from unnest(array['carta_reserva','ppjb_reserva','ppjb_parcela','ppjb_construccion','poa_notario']) s loop
    if exists (select 1 from public.plantilla_contrato_versiones v where v.empresa = 'sandal_woods' and v.slug = r.slug and v.origen = 'empresa') then
      continue;   -- idempotente
    end if;
    select * into v_seed from public.plantilla_contrato_versiones v where v.empresa = 'sandal_woods' and v.slug = r.slug and v.origen = 'semilla';
    if not found then raise exception 'Falta la semilla v1 de sandal_woods/%', r.slug; end if;
    select c.cuerpo_html into v_cuerpo0 from public.plantilla_contrato_cuerpos c where c.version_id = v_seed.id;
    v_body := public._plantilla_sin_notas(v_cuerpo0);
    if (length(v_body) - length(replace(v_body, c_viejo, ''))) / length(c_viejo) <> 1 then
      raise exception '%: se esperaba exactamente un titulo «%»', r.slug, c_viejo;
    end if;
    v_body := replace(v_body, c_viejo, c_nuevo);

    v_esq := public._plantilla_esqueleto('sandal_woods', r.slug);
    perform public._plantilla_exige_valido(v_body, 'sandal_woods', r.slug);
    if exists (select 1 from public.plantilla_solo_global s where s.slug = r.slug) then
      -- ruta del super global (_plantilla_exige_bloques): solo cambia el titulo
      if public._plantilla_ws(replace(v_body, c_nuevo, c_viejo)) is distinct from public._plantilla_ws(public._plantilla_sin_notas(v_esq)) then
        raise exception '%: ademas del titulo cambia otra cosa', r.slug;
      end if;
    else
      perform public._plantilla_exige_bloques(v_body, v_esq, 'sandal_woods', r.slug);
    end if;
    v_bloq := public._plantilla_motivo_bloqueo(v_body, 'sandal_woods', r.slug);
    if v_bloq is not null then raise exception '%: no activable: %', r.slug, v_bloq; end if;

    v_hash := public._plantilla_hash(v_body);
    v_bytes := pg_catalog.octet_length(v_body);
    v_idiomas := array_remove(array[
      case when v_body like '%data-lang="es"%' then 'es' end,
      case when v_body like '%data-lang="en"%' then 'en' end,
      case when v_body like '%data-lang="id"%' then 'id' end], null);
    select coalesce(max(v.version), 0) + 1 into v_n from public.plantilla_contrato_versiones v where v.empresa = 'sandal_woods' and v.slug = r.slug;
    insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, hereda_de, autor, motivo)
    values ('sandal_woods', r.slug, v_n, 'borrador', 'empresa', v_idiomas, v_hash, v_bytes, true, null, v_seed.id,
            'estudio (orden del owner 8-oct-2026)',
            'v2 de Sandal Woods: sociedad firmante por marcador (titulo con {{prom_marca}} en vez de LAWANG), sin notas de autor. Texto contractual identico a la semilla.')
    returning id into v_id;
    insert into public.plantilla_contrato_cuerpos (version_id, cuerpo_html) values (v_id, v_body);
  end loop;
end
$mig$;
