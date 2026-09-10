-- Un lead que entra despues de hoy NO tenia fila en `lead_estado`, y eso rompia el tablero
-- entero para el: la vista lo pinta bien (coalesce a 'nuevo'), pero el primer intento de
-- moverlo escribe sobre una fila que no existe -> 0 filas -> el servidor devuelve 409
-- «otra persona la movio» y el navegador recarga. Para siempre, con cada lead nuevo.
-- Reproducido con un lead de prueba antes de escribir esto, no deducido leyendo el codigo.
--
-- Se arregla en el origen y no en el endpoint: el estado nace con el lead, punto. Va como
-- AFTER INSERT a proposito -- el upsert de R13 (`merge-duplicates`) dispara los triggers de
-- insercion solo para las filas que de verdad son nuevas; para las que chocan dispara los
-- de modificacion. Asi que esto NO rompe la invariante que pidio Datos: R13 sigue sin
-- escribir jamas en `estado`, `responsable` ni `estado_desde`.
create or replace function public.lead_estado_al_nacer()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.lead_estado (lead_id, estado, estado_desde)
    values (new.id, 'nuevo', new.created_at)
    on conflict (lead_id) do nothing;   -- idempotente: reponer un lead no pisa su estado
    return null;
end $$;

-- destructivo-ok: se borra un TRIGGER para recrearlo dos lineas mas abajo, que es el patron
-- idempotente normal de `create or replace` para triggers (Postgres no tiene
-- `create or replace trigger` en todas las versiones). No se borra ninguna fila ni ninguna
-- tabla; si esta migracion se aplica dos veces, el resultado es el mismo.
drop trigger if exists trg_lead_estado_al_nacer on public.leads;
create trigger trg_lead_estado_al_nacer
    after insert on public.leads
    for each row execute function public.lead_estado_al_nacer();

-- Y los que hayan entrado entre el despliegue y este arreglo (el lead de prueba con el que
-- se reprodujo el fallo, o cualquiera que R13 haya bajado mientras tanto).
insert into public.lead_estado (lead_id, estado, estado_desde)
select l.id, 'nuevo', l.created_at from public.leads l
on conflict (lead_id) do nothing;;
