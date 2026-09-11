-- Backfill de la atribucion de las 45 ventas firmadas. 11-sep-2026, a peticion del owner
-- ("sales@lawangproperties.com pertenece a Carmen en /usuarios/, no puedes asignarlo ya?").
--
-- POR QUE AHORA SI, SI AYER SE DIJO QUE `creado_por` NO ERA EL CLOSER.
-- Lo que hacia dudoso el atajo era no saber si esas cuentas eran personas o buzones. Ya se
-- sabe, y son personas con nombre en `usuarios`: sales@ es Carmen, hello@ es Yesy, y los
-- otros seis igual. El owner ademas confirma que los closers estaran siempre dados de alta
-- ahi. Y la discrepancia que se habia usado como prueba resulto afectar a UN contrato de 45:
-- medido hoy, solo CR00019 (Carmen) cuelga de un padre creado por otra cuenta (RP00040, del
-- owner). Con eso, pre-atribuir y que revisen es mucho mejor que 45 desplegables a mano.
--
-- LO QUE ESTO NO ES: una verdad definitiva. Es una PROPUESTA con la mejor pista disponible,
-- y por eso queda marcada como tal en el log (`autor` = 'backfill 11-sep...'), se puede
-- corregir desde el panel una a una, y cada correccion deja su propia fila. Lo que NO se
-- hace es fingir que el dato siempre estuvo: quien mire el historial vera que estas 45 las
-- puso una migracion y no una persona.
--
-- Se excluye lo que no se puede atribuir: los 2 contratos sin `creado_por`. Se quedan en la
-- cesta "(sin atribuir)" del panel, visible, que es justo para lo que existe esa cesta.

insert into public.contrato_closer (contrato_id, closer_email, asignado_por, asignado_en)
select c.id, lower(btrim(c.creado_por)),
       'backfill 11-sep-2026 desde creado_por (propuesta, revisable)', now()
  from public.contratos c
 where coalesce(c.bloqueado, false)
   and c.precio_total is not null
   and nullif(btrim(coalesce(c.creado_por, '')), '') is not null
   -- solo cuentas que existen y estan activas: atribuir a un correo que no es de nadie
   -- dejaria una fila en el ranking imposible de corregir desde el desplegable.
   and exists (select 1 from public.usuarios u
                where lower(u.email) = lower(btrim(c.creado_por)) and u.activo)
   and not exists (select 1 from public.contrato_closer k where k.contrato_id = c.id);

insert into public.contrato_closer_log (contrato_id, de, a, autor)
select k.contrato_id, null, k.closer_email, k.asignado_por
  from public.contrato_closer k
 where k.asignado_por like 'backfill 11-sep-2026%'
   and not exists (select 1 from public.contrato_closer_log g where g.contrato_id = k.contrato_id);
