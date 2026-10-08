-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «editor de textos de contrato» (encargos/20261008_lawang_editor_textos_contrato.md) · E9 · segunda mitad: un CONTRATO PROPIO se puede EMITIR como contrato real (8-oct-2026).
-- PROBLEMA (informe de Datos sobre 20261010030000): el contrato propio se redactaba y se activaba, pero `contratos.tipo` tenia un CHECK con 17 tipos fijos, `_plantilla_slug_de_tipo` un mapa fijo,
--   `set_contrato_numero` un CASE fijo (tipo desconocido = excepcion) y al activar nadie quitaba el flag `archivada` del contrato (nace oculto de los selectores de emision).
-- QUE HACE:
--   1. `contratos_tipo_check` pasa de «uno de los 17» a «uno de los 17, o con forma de slug». La EXISTENCIA y la EMPRESA las decide el trigger `trg_00_contrato_tipo_valido`
--      (antes de insertar o de cambiar tipo/proyecto): un tipo fuera de los 17 solo vale si es el slug de un contrato propio cuya `empresa` es la del proyecto del contrato. Ni una lista fija ni
--      una tabla de tipos nueva: la fuente es `plantillas_contrato`, que ya tiene dueño. Los 17 de siempre y todos los contratos existentes pasan sin consultar nada (primera linea del trigger).
--   2. `_plantilla_slug_de_tipo(tipo)`: los 17 por el mapa de siempre; un tipo propio -> el propio slug (existe y es de una empresa). Mismo nombre y firma, asi plantilla_contrato_fija y el resto no cambian.
--   3. `set_contrato_numero`: el CASE de los 17 queda IDENTICO; en el `else`, un tipo propio toma la serie comun CX (secuencia nueva `contratos_cx_seq`, formato CX00001). Un tipo que no es ni lo uno ni lo otro
--      sigue dando la misma excepcion. Sigue SIN security definer (la lectura de la plantilla pasa por RLS: el trigger 1 ya garantizo que es de la empresa del contrato).
--   4. Al ACTIVAR una version de un contrato propio, `archivada` pasa a false; al quedarse sin ninguna activa vuelve a true (trigger sobre las versiones; los 20 del estudio no se tocan: empresa null).
--   5. RPC de lectura `plantilla_contratos_propios_activos(p_empresa)` para el selector del generador: slug y nombre de los propios con version activa; cualquier agente con la empresa en alcance.
-- NO HACE: los mapas del front (TIPO_ES/TIPO_LABEL/CONTRACT_TIPO/TIPO_PREFIX de contracts/app.html y vocabulario.js), ni asignar el tipo propio a un agente (usuarios.tipos_contrato lo gobierna el admin).
-- Fuente generadora: contracts/sql/tipos_de_contrato.sql se actualiza en el mismo commit (si no, al volver a correrlo borraria esta regla).
-- destructivo-ok: reemplaza un CHECK por otro MAS ANCHO (todo lo que cabia sigue cabiendo; sin riesgo para filas), crea una secuencia, 3 funciones, 2 triggers y redefine 2 funciones; no toca filas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_editor_e9_tipo_propio.sql

-- ------------------------------------------------------------------------------------------------------------------ 1 · el tipo
alter table public.contratos drop constraint contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check check (
  tipo = any (array['reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer', 'carta_reserva', 'carta_reserva_ampliada', 'acuerdo_comercial', 'protocolo_operativo',
                    'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa', 'poa', 'cc00014_timon', 'carta_reserva_pma', 'adenda', 'carta_reserva_investor_deck']::text[])
  or tipo ~ '^[a-z][a-z0-9_]{2,59}$');

create function public._trg_contrato_tipo_valido() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_emp text;
begin
  if new.tipo = any (array['reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer', 'carta_reserva', 'carta_reserva_ampliada', 'acuerdo_comercial', 'protocolo_operativo',
                           'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa', 'poa', 'cc00014_timon', 'carta_reserva_pma', 'adenda', 'carta_reserva_investor_deck']::text[]) then
    return new;
  end if;
  v_emp := case when new.proyecto_id is null then null else public.empresa_de_proyecto(new.proyecto_id) end;
  if v_emp is null or not exists (select 1 from public.plantillas_contrato t where t.slug = new.tipo and t.empresa = v_emp) then
    raise exception 'Tipo de contrato no valido para esta empresa: %', new.tipo using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function public._trg_contrato_tipo_valido() from public, anon, authenticated, service_role;
create trigger trg_00_contrato_tipo_valido before insert or update of tipo, proyecto_id on public.contratos
  for each row execute function public._trg_contrato_tipo_valido();

-- ------------------------------------------------------------------------------------------------------------------ 2 · tipo -> plantilla
create or replace function public._plantilla_slug_de_tipo(p_tipo text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select m.slug from (values
      ('reserva_parcela', 'ppjb_parcela'), ('construccion', 'ppjb_construccion'), ('contrato_general', 'ppjb_reserva'), ('commercial_offer', 'commercial_offer'),
      ('carta_reserva', 'carta_reserva'), ('carta_reserva_ampliada', 'carta_reserva_ampliada'), ('acuerdo_comercial', 'commercial_collaboration'),
      ('protocolo_operativo', 'colaborador_operativo'), ('ppjb_bonian', 'ppjb_bonian'), ('ppjb_bonian_c2', 'ppjb_bonian_c2'), ('hak_sewa_notario', 'hak_sewa_notario'),
      ('carta_reserva_hak_sewa', 'carta_reserva_hak_sewa'), ('carta_reserva_pma', 'carta_reserva_pma'), ('poa', 'poa_notario'), ('cc00014_timon', 'cc00014_timon'),
      ('adenda', 'adenda'), ('carta_reserva_investor_deck', 'carta_reserva_investor_deck')
    ) as m(tipo, slug) where m.tipo = p_tipo),
    (select t.slug from public.plantillas_contrato t where t.slug = p_tipo and t.empresa is not null))
$$;
revoke all on function public._plantilla_slug_de_tipo(text) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------------------------ 3 · numeracion (serie comun CX para los propios)
create sequence if not exists public.contratos_cx_seq;
create or replace function public.set_contrato_numero() returns trigger language plpgsql set search_path to '' as $$
declare
  n bigint;
  prefix text;
  seqname text;
begin
  if new.numero is not null then
    return new;
  end if;
  case new.tipo
    when 'reserva_parcela' then prefix := 'RP'; seqname := 'public.contratos_rp_seq';
    when 'construccion' then prefix := 'CC'; seqname := 'public.contratos_cc_seq';
    when 'contrato_general' then prefix := 'CG'; seqname := 'public.contratos_cg_seq';
    when 'commercial_offer' then prefix := 'CO'; seqname := 'public.contratos_co_seq';
    when 'carta_reserva' then prefix := 'CR'; seqname := 'public.contratos_cr_seq';
    when 'carta_reserva_ampliada' then prefix := 'CA'; seqname := 'public.contratos_ca_seq';
    when 'acuerdo_comercial' then prefix := 'AC'; seqname := 'public.contratos_ac_seq';
    when 'protocolo_operativo' then prefix := 'PO'; seqname := 'public.contratos_po_seq';
    when 'ppjb_bonian' then prefix := 'PB'; seqname := 'public.contratos_pb_seq';
    when 'ppjb_bonian_c2' then prefix := 'C2'; seqname := 'public.contratos_c2_seq';
    when 'hak_sewa_notario' then prefix := 'HS'; seqname := 'public.contratos_hs_seq';
    when 'carta_reserva_hak_sewa' then prefix := 'CH'; seqname := 'public.contratos_ch_seq';
    when 'poa' then prefix := 'PA'; seqname := 'public.contratos_poa_seq';
    when 'cc00014_timon' then prefix := 'CC'; seqname := 'public.contratos_cc_seq';
    when 'carta_reserva_pma' then prefix := 'CP'; seqname := 'public.contratos_cp_seq';
    when 'adenda' then prefix := 'AD'; seqname := 'public.contratos_ad_seq';
    when 'carta_reserva_investor_deck' then prefix := 'CD'; seqname := 'public.contratos_cd_seq';
    else
      -- contrato propio de una empresa (E9): serie comun CX. Que es de la empresa del contrato ya lo garantizo trg_00_contrato_tipo_valido.
      if exists (select 1 from public.plantillas_contrato t where t.slug = new.tipo and t.empresa is not null) then
        prefix := 'CX'; seqname := 'public.contratos_cx_seq';
      else
        raise exception 'Tipo de contrato sin numeracion definida: %', new.tipo;
      end if;
  end case;
  n := nextval(seqname);
  new.numero := prefix || lpad(n::text, 5, '0');
  return new;
end;
$$;

-- ------------------------------------------------------------------------------------------------------------------ 4 · activar quita `archivada`; quedarse sin activa la vuelve a poner
create function public._trg_plantilla_propia_archivada() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.plantillas_contrato t
     set archivada = not exists (select 1 from public.plantilla_contrato_versiones v where v.empresa = t.empresa and v.slug = t.slug and v.estado = 'activa' and v.borrada_en is null)
   where t.slug = new.slug and t.empresa is not null
     and t.archivada is distinct from (not exists (select 1 from public.plantilla_contrato_versiones v where v.empresa = t.empresa and v.slug = t.slug and v.estado = 'activa' and v.borrada_en is null));
  return null;
end $$;
revoke all on function public._trg_plantilla_propia_archivada() from public, anon, authenticated, service_role;
create trigger plantilla_propia_archivada after insert or update of estado, borrada_en on public.plantilla_contrato_versiones
  for each row execute function public._trg_plantilla_propia_archivada();

-- ------------------------------------------------------------------------------------------------------------------ 5 · lista para el selector del generador
create function public.plantilla_contratos_propios_activos(p_empresa text) returns table (slug text, nombre text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_agente() and public.empresa_en_alcance(p_empresa)) then
    raise exception 'No tienes acceso a los contratos de esa empresa' using errcode = '42501';
  end if;
  return query
    select t.slug, t.nombre from public.plantillas_contrato t
     where t.empresa = p_empresa
       and exists (select 1 from public.plantilla_contrato_versiones v where v.empresa = p_empresa and v.slug = t.slug and v.estado = 'activa' and v.borrada_en is null)
     order by t.nombre, t.slug;
end $$;
revoke all on function public.plantilla_contratos_propios_activos(text) from public, anon, service_role;
grant execute on function public.plantilla_contratos_propios_activos(text) to authenticated;
comment on function public.plantilla_contratos_propios_activos(text) is 'Selector del generador de contratos: solo slug y nombre de los contratos propios de la empresa con alguna version activa (E9, 8-oct-2026). Llamador: contracts/app.html (pendiente de cablear).';
