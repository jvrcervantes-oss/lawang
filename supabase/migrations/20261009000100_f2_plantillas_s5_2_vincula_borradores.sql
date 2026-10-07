-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S5 (generador) · migracion 2/2 (7-oct-2026): FIJA CADA CONTRATO AL TEXTO QUE YA USABA.
--   Vincula (tabla contrato_plantilla_version, NO `contratos`: sin columna ni trigger nuevo) cada contrato que aun se puede editar a la semilla v1 de SU empresa y de SU plantilla
--   (tipo del contrato -> plantilla por _plantilla_slug_de_tipo; empresa = la del proyecto del contrato). La semilla es la copia byte a byte del fichero que ese contrato ya usaba,
--   asi que al reabrirlo no cambia ni una letra: lo que cambia es que desde hoy la version queda ESCRITA y ya no depende de que alguien edite un fichero.
--   Quedan SIN vincular, a proposito: los bloqueados/firmados (su texto es el PDF), los que tienen alguna fila en contrato_firmas (CC00109 entre ellos: ronda de firma en curso o anulada;
--   el trigger del vinculo los rechaza incluso para postgres), los 3 sin proyecto y los de proyecto sin empresa. Vuelven a ser candidatos solo con una decision explicita.
--   Idempotente (on conflict do nothing) y sin ids a mano. `fijado_por` = 'S5 carga inicial'. Medido el 7-oct-2026 antes de aplicar: 154 candidatos.
--   El cuerpo de la semilla se vuelve a comprobar: hash de la fila == sha256 del cuerpo guardado (si no, aborta).
-- destructivo-ok: solo inserta filas en la tabla nueva contrato_plantilla_version (sin tocar contratos ni versiones)
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s5_2.sql
do $$
declare n_semillas int; n_malas int; n_ins int;
begin
  select count(*) into n_semillas from public.plantilla_contrato_versiones where origen = 'semilla' and version = 1;
  if n_semillas <> 40 then raise exception 'Se esperaban 40 semillas v1 y hay %: no se vincula nada', n_semillas; end if;
  select count(*) into n_malas from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.origen = 'semilla' and public._plantilla_hash(c.cuerpo_html) is distinct from v.hash;
  if n_malas <> 0 then raise exception '% semillas con hash distinto a su cuerpo: no se vincula nada', n_malas; end if;

  insert into public.contrato_plantilla_version (contrato_id, version_id, fijado_por)
  select c.id, v.id, 'S5 carga inicial'
    from public.contratos c
    join public.proyectos p on p.id = c.proyecto_id
    join public.plantilla_contrato_versiones v
      on v.empresa = p.empresa and v.slug = public._plantilla_slug_de_tipo(c.tipo) and v.origen = 'semilla' and v.version = 1
   where p.empresa is not null
     and not c.bloqueado
     and not exists (select 1 from public.contrato_firmas f where f.contrato_id = c.id)
  on conflict (contrato_id) do nothing;
  get diagnostics n_ins = row_count;
  raise notice 'S5: % contratos vinculados a la semilla v1 de su empresa', n_ins;
end $$;
