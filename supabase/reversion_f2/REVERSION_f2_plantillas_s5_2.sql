-- Reversion de la migracion 20261009000100 (S5 · vincula los borradores a la semilla v1, 7-oct-2026).
-- Quita SOLO los vinculos que puso esa migracion (fijado_por = 'S5 carga inicial'), nada mas. Si alguno de esos contratos se ha bloqueado o ha entrado en ronda de firma desde entonces,
-- el trigger del vinculo impediria el DELETE: se apaga solo durante este borrado (el vinculo de un contrato que ya firmo no se toca: se avisa y se deja).
-- destructivo-ok: borra filas de contrato_plantilla_version creadas por la migracion que se revierte (tabla de vinculos, no contratos)
begin;
alter table public.contrato_plantilla_version disable trigger trg_contrato_plantilla_version;
delete from public.contrato_plantilla_version l
 where l.fijado_por = 'S5 carga inicial'
   and not exists (select 1 from public.contratos c where c.id = l.contrato_id and c.bloqueado)
   and not exists (select 1 from public.contrato_firmas f where f.contrato_id = l.contrato_id);
alter table public.contrato_plantilla_version enable trigger trg_contrato_plantilla_version;
do $$ declare n int; begin
  select count(*) into n from public.contrato_plantilla_version where fijado_por = 'S5 carga inicial';
  if n > 0 then raise notice 'Quedan % vinculos de S5 sobre contratos ya firmados o en firma: se conservan (son historia)', n; end if;
end $$;
commit;
