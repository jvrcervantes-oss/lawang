-- «Es obra» pasa a ser un dato del catálogo, no una lista a mano (13-oct-2026). Sigue a 20261013022113.
--
-- Por qué: 20261013022113 dejó la lista ('construccion', 'cc00014_timon') escrita en tres funciones. El
-- revisor lo paró: desde E9 (20261010040000) una empresa puede crear su propio tipo de contrato, y una
-- lista en código no se entera; el precedente de estas mismas funciones (20260924130000) ya lee las Cartas
-- de contrato_tipo_etapa y no de una lista. Una sola fuente: la columna contrato_tipo_etapa.es_obra.
--
-- Qué hace:
--   1. contrato_tipo_etapa.es_obra (boolean, false por defecto) = true en 'construccion' y 'cc00014_timon'.
--      La tabla ya es de solo lectura para authenticated y lw_lector (SELECT + RLS de lectura, medido hoy):
--      nadie desde el navegador puede marcar un tipo como obra.
--      Se corrige la nota de cc00014_timon («Contrato de compra»): es una Construcción de ejemplar único,
--      serie CC (contracts/assets/vocabulario.js:59; su único contrato, CC00088, cuelga del Bloqueo RP00026).
--   2. Las tres funciones (unidad_parte_cobrada_interno, unidad_parte_cobrada_split,
--      comisiones_evaluar_contrato) cambian la lista por la consulta al catálogo. Mismo parche de función
--      viva con marca de una línea que 20261013022113; idempotente.
--
-- Efecto medido: ninguno sobre los datos de hoy (mismas 22 unidades con obra firmada; la prueba
-- supabase/pruebas/obra_firmada_solo_obra.sql lo comprueba antes y después). Un tipo propio de E9 no está en
-- el catálogo, así que NO cuenta como obra hasta que alguien lo marque: es lo seguro (contar obra que no lo
-- es mueve la barra y el snapshot de comisiones); quién lo marca y desde dónde está en pendientes (LAW-551 en
-- contexto/pendientes.md de la agencia).
--
-- Vuelta atrás: los mismos parches con (marca, nuevo) invertidos; la columna puede quedarse (nadie más la lee).

alter table public.contrato_tipo_etapa add column if not exists es_obra boolean not null default false;
comment on column public.contrato_tipo_etapa.es_obra is
  'true = un contrato de este tipo, hijo y firmado, es «obra firmada» de la parcela (barra de obra del inventario, estado y comisiones). Fuente única desde 13-oct-2026; la leen unidad_parte_cobrada_interno, unidad_parte_cobrada_split y comisiones_evaluar_contrato.';
update public.contrato_tipo_etapa set es_obra = true
 where tipo in ('construccion', 'cc00014_timon') and not es_obra;
update public.contrato_tipo_etapa set nota = 'Contrato de construccion de ejemplar unico (serie CC, CC00088)'
 where tipo = 'cc00014_timon' and nota = 'Contrato de compra (ejemplar propio)';

do $$
declare
  p   record;
  def text;
  n   int;
begin
  if (select count(*) from public.contrato_tipo_etapa where es_obra) <> 2 then
    raise exception 'obra_firmada: se esperaban 2 tipos de obra en contrato_tipo_etapa';
  end if;
  for p in
    select * from (values
      ('public.unidad_parte_cobrada_interno(uuid)'::regprocedure,
       'hj.tipo in (''construccion'', ''cc00014_timon'')',
       'exists (select 1 from public.contrato_tipo_etapa e where e.tipo = hj.tipo and e.es_obra)'),
      ('public.unidad_parte_cobrada_split(uuid)'::regprocedure,
       'hj.tipo in (''construccion'', ''cc00014_timon'')',
       'exists (select 1 from public.contrato_tipo_etapa e where e.tipo = hj.tipo and e.es_obra)'),
      ('public.comisiones_evaluar_contrato(uuid)'::regprocedure,
       'h.tipo in (''construccion'', ''cc00014_timon'')',
       'exists (select 1 from public.contrato_tipo_etapa e where e.tipo = h.tipo and e.es_obra)')
    ) as t(fn, marca, nuevo)
  loop
    def := pg_get_functiondef(p.fn);
    if position(p.nuevo in def) > 0 then
      continue;  -- ya aplicado
    end if;
    n := (length(def) - length(replace(def, p.marca, ''))) / length(p.marca);
    if n <> 1 then
      raise exception 'obra_firmada: la marca «%» aparece % veces en % (se esperaba 1)', p.marca, n, p.fn;
    end if;
    execute replace(def, p.marca, p.nuevo);
  end loop;
end
$$;
