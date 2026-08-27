-- 27-ago-2026, encargo del owner: «los no firmados cambiarlos a Sumba Hills».
--
-- El resort «SandalWoods» pasó a llamarse «Sumba Hills» (el catálogo ya cambió
-- en `proyectos.resort`). Aquí se migra lo que quedó ESCRITO dentro de
-- `contratos.datos->fields->resort`.
--
-- 🔴 TRES ESTADOS, NO DOS. El primer intento filtraba «firmado / no firmado» y
-- la base lo rechazó: el trigger `contrato_no_editable_en_firma` paró el UPDATE
-- por RP00021, que no está firmado pero SÍ enviado a firma, con el enlace vivo
-- en el buzón de alguien. Un documento cuyo enlace de firma ya salió no puede
-- cambiar por debajo del que lo va a firmar. La base sabía algo que yo no había
-- preguntado, y ese rechazo es el guardarraíl funcionando.
--   · 1 firmado (CR00021)         → no se toca
--   · 1 enviado a firma (RP00021) → no se toca
--   · 73 migrables                → estos
--
-- El respaldo se queda EN LA BASE: deshacer esto es una sola sentencia contra
-- esa tabla, y un fichero con 73 UUID en el repo es un fichero que nadie
-- encuentra el día que hace falta.

create table if not exists public._respaldo_resort_sandalwoods as
select c.id, c.numero,
       c.datos->'fields'->>'resort' as resort_antes,
       now() as guardado_en
from public.contratos c
where c.datos->'fields'->>'resort' = 'SandalWoods'
  and not c.bloqueado
  and c.pdf_firmado_path is null
  and c.pdf_firmado_hash is null
  and not exists (select 1 from public.contrato_firmas f
                   where f.contrato_id = c.id and f.estado in ('pendiente','firmado'));

comment on table public._respaldo_resort_sandalwoods is
  'Respaldo del renombrado de resort SandalWoods → Sumba Hills (27-ago-2026). Para deshacer: update contratos c set datos = jsonb_set(c.datos, ''{fields,resort}'', to_jsonb(r.resort_antes)) from _respaldo_resort_sandalwoods r where r.id = c.id;';

update public.contratos c
   set datos = jsonb_set(c.datos, '{fields,resort}', '"Sumba Hills"'::jsonb, false)
 where c.datos->'fields'->>'resort' = 'SandalWoods'
   and not c.bloqueado
   and c.pdf_firmado_path is null
   and c.pdf_firmado_hash is null
   and not exists (select 1 from public.contrato_firmas f
                    where f.contrato_id = c.id and f.estado in ('pendiente','firmado'));
