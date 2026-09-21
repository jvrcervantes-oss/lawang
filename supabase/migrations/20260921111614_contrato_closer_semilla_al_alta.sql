-- Autoatribución de closer al ALTA del contrato — 21-sep-2026, encargo del owner:
-- "asume que la venta es de quien hace el contrato".
--
-- QUÉ HACE: en cuanto se inserta un contrato, siembra `contrato_closer` con
-- `NEW.creado_por` — pero SOLO cuando el contrato es RAÍZ (`contrato_padre_id
-- is null`). El motor de comisiones (`comisiones_evaluar_contrato_fn.sql`,
-- sección "closer de la RAÍZ") solo lee `contrato_closer` de la raíz de la
-- cadena; sembrarlo también en un hijo dejaría una fila muerta que nadie
-- consulta y que confunde en la pantalla de atribución (parecería que el hijo
-- tiene closer propio cuando el que cuenta es el de su raíz).
--
-- ES UN VALOR DE PARTIDA EDITABLE, NO LA VERDAD — dilo tú, quien lea esto
-- dentro de unos meses, antes de tratarlo como un hecho. La migración
-- 20260911020137 (atribución de ventas) ya documentó un caso real donde
-- `creado_por` NO era el closer real: RP00040 lo creó jvr.cervantes y su hijo
-- CR00019 lo creó sales@ — mismo comprador, mismo negocio, dos autores.
-- Restringir el sembrado a la raíz reduce ese riesgo (dentro de una misma
-- cadena ya no hay dos autores compitiendo, el hijo no siembra nada) pero NO
-- LO ELIMINA DEL TODO: quien pulsa "crear" en la intranet no siempre es quien
-- cerró la venta sobre el terreno. Por eso esto sigue siendo corregible a
-- mano — desde Comisiones (`crm_contrato_closer_set`, que este trigger nunca
-- sustituye ni pisa si ya hay fila) y ahora también desde la ficha del
-- contrato en /intranet/v4/ — y por eso NO basta con sembrarlo una vez y
-- olvidarse: sigue haciendo falta mirar los casos raros, este trigger solo
-- evita partir de "sin atribuir" en el 100% de las ventas nuevas.
--
-- `asignado_por = 'sistema:alta'` (nunca un email real) para que el histórico
-- (`contrato_closer_log`) distinga a simple vista una atribución automática
-- de una corregida a mano por alguien con el permiso 'ranking'.
--
-- VALIDACIÓN: mismo criterio que ya exige `crm_contrato_closer_set` para un
-- `p_email` manual — no se siembra con un correo que no sea hoy un
-- `usuarios.activo = true` real, para no crear una fila que apunta a nadie.
--
-- NO ES RETROACTIVO: solo dispara en el INSERT de contratos nuevos a partir
-- de esta migración. El histórico de "sin atribuir" no se toca aquí — si el
-- owner pide backfill del histórico, es una migración aparte, con su propia
-- revisión previa.
--
-- `on conflict (contrato_id) do nothing`: por si un `contrato_id` se
-- reinsertase tras un delete+insert manual y ya llevara atribución (no
-- debería pasar en un INSERT normal, pero nunca se pisa una fila existente).

create or replace function public.crm_contrato_closer_semilla()
returns trigger
language plpgsql volatile security definer set search_path to ''
as $$
begin
  -- Solo la raíz: el motor de comisiones nunca lee el closer de un hijo.
  if NEW.contrato_padre_id is not null then
    return NEW;
  end if;

  if NEW.creado_por is null then
    return NEW;
  end if;

  -- Mismo gate que crm_contrato_closer_set: no se siembra con un correo que
  -- no sea hoy un usuario activo real de la intranet.
  if not exists (
    select 1 from public.usuarios u
     where lower(u.email) = lower(NEW.creado_por) and u.activo
  ) then
    return NEW;
  end if;

  insert into public.contrato_closer (contrato_id, closer_email, asignado_por, asignado_en)
       values (NEW.id, NEW.creado_por, 'sistema:alta', now())
  on conflict (contrato_id) do nothing;

  if found then
    insert into public.contrato_closer_log (contrato_id, de, a, autor)
         values (NEW.id, null, NEW.creado_por, 'sistema:alta');
  end if;

  return NEW;
end;
$$;

-- destructivo-ok: drop-if-exists idempotente de un trigger que esta misma migración
-- crea por primera vez (no existe aún en producción); es el patrón estándar del
-- repo para poder reaplicar la migración sin duplicar el trigger.
drop trigger if exists trg_contrato_closer_semilla on public.contratos;
create trigger trg_contrato_closer_semilla
  after insert on public.contratos
  for each row execute function public.crm_contrato_closer_semilla();
;
