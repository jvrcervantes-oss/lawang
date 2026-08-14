-- LAW-51 (guardarrail de "mismo comprador") + LAW-50 (la Carta cuelga del
-- Bloqueo) -- 14-ago-2026, decision del owner.
--
-- Contexto: el 14-ago se abrio el traspaso Carta de Reserva -> Bloqueo de
-- Parcela (parcela_traspaso_carta_a_bloqueo.sql). Dejo dos huecos conocidos,
-- fichados como LAW-51 y LAW-50, y el caso real A4/CR00019->RP00040 los puso a
-- la vista. Se cierran los dos aqui, en el mismo sitio donde vive la regla.
--
-- ---------------------------------------------------------------------------
-- LAW-51 -- nada comprobaba que el comprador fuese el mismo
-- ---------------------------------------------------------------------------
-- El traspaso movia la parcela de un contrato a otro sin mirar a nombre de
-- quien estaba cada uno: un error de tecleo en el selector de parcela podia
-- pasarle la parcela de un cliente a otro, en silencio y sin dejar rastro.
--
-- QUE SE COMPARA, y por que este criterio y no el nombre: el pasaporte y el
-- email, que es EXACTAMENTE lo que `sincronizar_compradores` usa para decidir
-- si dos filas son la misma persona (pasaporte primero, email despues) y por
-- tanto lo que crea o reconoce la ficha de `clients`. El nombre se descarto a
-- proposito: es texto libre y compararlo por igualdad daria falsos bloqueos por
-- una tilde o un segundo apellido, que es justo la friccion que el traspaso
-- venia a quitar.
--
-- POR QUE SE LEE DE `datos` Y NO DE `contrato_compradores`, que seria la
-- relacion "buena": porque `contrato_compradores` lo rellena OTRO disparador
-- (trg_compradores_desde_datos) sobre la misma fila y en la misma sentencia.
-- Depender de el obligaria a depender del orden de disparo entre dos triggers
-- AFTER -- que hoy sale bien por orden alfabetico ("c" antes que "s"), pero es
-- una coincidencia del nombre, no una garantia que nadie haya escrito. Y encima
-- ese disparador se traga sus propios errores (`raise warning`), asi que puede
-- dejar la tabla vacia sin que nada falle. Leyendo el jsonb la comprobacion es
-- autosuficiente: no le importa quien corre antes ni si el alta de ficha fallo.
--
-- QUE PASA SI NO SE PUEDE COMPROBAR (decision del owner, 14-ago): se BLOQUEA.
-- Un contrato sin pasaporte ni email no permite afirmar que el comprador
-- coincide, y se eligio proteccion maxima antes que dejar pasar la duda. Hoy
-- son 4 contratos de 36 los que estan en ese caso; al intentar traspasarlos
-- saldra un mensaje que dice exactamente que falta y donde.
--
-- ---------------------------------------------------------------------------
-- LAW-50 -- las dos mitades de la venta salian como operaciones separadas
-- ---------------------------------------------------------------------------
-- Se enlazan por `contrato_padre_id`, PERO AL REVES de como suena: el padre es
-- el BLOQUEO y la Carta pasa a ser su hija. La lectura literal (el Bloqueo
-- colgando de la Carta) parece la natural porque respeta el orden cronologico,
-- y esta descartada por tres motivos verificados contra el codigo de hoy:
--
--   1. `avanza_unidad_por_cobro` resuelve la raiz con
--      `coalesce(contrato_padre_id, id)` -- UN SOLO SALTO -- y luego hace
--      `update unidades ... where contrato_id = v_raiz_id`. Pero
--      `unidades.contrato_id` apunta SIEMPRE al contrato de suelo, o sea al
--      Bloqueo. Si el Bloqueo pasara a tener padre, la raiz de un recibi seria
--      la Carta, la parcela no coincidiria con ninguna fila y el update tocaria
--      CERO filas: la parcela no avanzaria nunca a vendida/cobrada. Es la misma
--      cadena que se arreglo el 12-ago (estado_unidad_por_tipo_y_cobro.sql).
--   2. Operaciones pinta solo raices (`OPS.filter(o => !o.padre)`) y agrupa un
--      nivel (`op.padre ? [op.padre, ...op.padre.hijos] : [op, ...op.hijos]`).
--      Con Carta -> Bloqueo -> Construccion, la Construccion no seria ni raiz ni
--      hija de una raiz: DESAPARECERIA de la vista.
--   3. `borrar_operacion` recoge padre + hijos de un nivel, y su propio
--      comentario dice que se queda corto a proposito porque "no hay nietos".
--
-- Colgando la Carta del Bloqueo, en cambio, no hay que tocar NADA de eso: el
-- Bloqueo sigue siendo la raiz (que es lo que `unidades.contrato_id` ya conoce),
-- la Carta entra como hermana de la Construccion, y las tres salen en una sola
-- operacion. Ademas el deposito cobrado con la Carta pasa a sumar en el cluster
-- de la parcela, que es lo que ya prometia la regla "la cuota de reserva se
-- imputa al precio total".
--
-- CONSECUENCIA ACEPTADA POR EL OWNER: `borrar_operacion` arrastra los hijos, asi
-- que borrar la operacion del Bloqueo intentaria llevarse tambien la Carta. No
-- es un agujero abierto -- esa funcion ya se niega a borrar nada si UN SOLO
-- contrato de la cadena esta bloqueado y quien pide no es super admin, y una
-- Carta traspasada esta firmada por definicion.
--
-- ---------------------------------------------------------------------------
-- DE PROPINA: una Carta ya traspasada se habia quedado INMUTABLE
-- ---------------------------------------------------------------------------
-- Encontrado al intentar enlazar CR00019 con RP00040 (el traspaso de A4 que el
-- owner hizo a mano antes de que existiera LAW-50): el UPDATE lo rechazo el
-- propio disparador. Comprobado luego con una edicion normal y corriente
-- (cambiar `nombre_contrato` de CR00019): tambien muere.
--
-- Es un dano colateral del traspaso del 14-ago, anterior a este fichero y NO
-- detectado entonces. Antes del traspaso una Carta siempre retenia su parcela,
-- asi que `u.contrato_id <> new.id` no encontraba a nadie. Despues del traspaso
-- la parcela la lleva el Bloqueo, asi que al guardar cualquier cambio en la
-- Carta el disparador ve su parcela "ocupada por otro" y revienta con
-- 'ya esta asignada'. Efecto real: corregir una errata en una Carta traspasada
-- era imposible, y el mensaje senalaba a la parcela, no a la causa.
--
-- Arreglo: si el que se guarda es una Carta cuya parcela lleva YA un Bloqueo
-- del MISMO comprador, es una Carta sucedida por su Bloqueo -- se deja guardar
-- y se sale sin tocar la parcela. Lo segundo es tan importante como lo primero:
-- el disparador termina con `update unidades set contrato_id = new.id`, asi que
-- dejarlo seguir le habria devuelto la parcela a la Carta, robandosela al
-- Bloqueo en silencio. Si los compradores NO coinciden no se toca nada y sigue
-- saliendo el error de siempre, que ahi si es el correcto.
--
-- ---------------------------------------------------------------------------
-- Comprobado antes de escribir (14-ago-2026)
-- ---------------------------------------------------------------------------
--   · `prosrc` de produccion == la version del repo, sin deriva.
--   · CR00019 y RP00040 (el caso real de A4) comparten pasaporte 33528987R y
--     email jjcarpin@gmail.com -> el traspaso ya hecho pasa el guardarrail.
--   · Unico recibi contra una Carta: REC00018, 5000 EUR, de CR00021
--     (Sumba Hills SH-105) -- otra parcela y sin traspasar, asi que enlazar no
--     mueve ningun estado ni ninguna cuenta ya existente.

-- ---------------------------------------------------------------------------
-- 1. Los identificadores con los que se reconoce a una persona
-- ---------------------------------------------------------------------------
-- Mismo criterio que `sincronizar_compradores`: pasaporte y email, en minusculas
-- y sin espacios de sobra. Recoge al Adquiriente I y a los adicionales, porque
-- una Carta a nombre de dos y un Bloqueo a nombre de uno de ellos son la misma
-- operacion. Devuelve `{}` (no null) cuando no hay ninguno, para que el que
-- llama distinga "no se pudo comprobar" de "no coincide".
create or replace function public.contrato_identificadores(p_datos jsonb)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(distinct t.v), '{}'::text[])
    from (
      select lower(btrim(p_datos->'fields'->>'adq1_pasaporte')) as v
      union all
      select lower(btrim(p_datos->'fields'->>'adq1_email'))
      union all
      select lower(btrim(e->>'pasaporte'))
        from jsonb_array_elements(
               case when jsonb_typeof(p_datos->'compradores') = 'array'
                    then p_datos->'compradores' else '[]'::jsonb end) e
      union all
      select lower(btrim(e->>'email'))
        from jsonb_array_elements(
               case when jsonb_typeof(p_datos->'compradores') = 'array'
                    then p_datos->'compradores' else '[]'::jsonb end) e
    ) t
   where nullif(t.v, '') is not null;
$$;

comment on function public.contrato_identificadores(jsonb) is
  'Pasaporte y email (adq1 + adicionales) en minusculas, para decidir si dos '
  'contratos son del mismo comprador. Mismo criterio que sincronizar_compradores.';

-- ---------------------------------------------------------------------------
-- 2. El disparador de siempre, con las dos reglas nuevas
-- ---------------------------------------------------------------------------
create or replace function public.sincroniza_unidad_contrato()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  cod          text := nullif(btrim(new.datos->'fields'->>'parcela_codigo'), '');
  proy         text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  cod_ant      text;
  ocupada      text;
  ocupada_id   uuid;
  ocupada_tipo text;
  traspaso_ok  boolean;
  ids_nuevo    text[];
  ids_ocupa    text[];
begin
  -- Reentrada: al final de este mismo disparador se cuelga la Carta del Bloqueo
  -- (LAW-50), y ese update sobre `contratos` vuelve a disparar esta funcion para
  -- la fila de la Carta. Sin este corte, esa segunda vuelta veria su parcela en
  -- manos del Bloqueo, con la Carta como tipo entrante -> traspaso_ok = false ->
  -- excepcion, y no se podria traspasar nada. El corte es estrecho a proposito:
  -- solo se salta cuando viene anidado Y no ha cambiado nada de lo que aqui
  -- importa, para no cegar una edicion de verdad que llegue anidada.
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and new.datos     is not distinct from old.datos
     and new.tipo      is not distinct from old.tipo
     and new.bloqueado is not distinct from old.bloqueado then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    cod_ant := nullif(btrim(old.datos->'fields'->>'parcela_codigo'), '');
    if cod_ant is distinct from cod then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id;
    end if;
  end if;

  if cod is null or proy is null then return new; end if;

  -- ahora importa QUIEN ocupa, no solo que haya alguien
  select c.id, c.numero, c.tipo, public.contrato_identificadores(c.datos)
    into ocupada_id, ocupada, ocupada_tipo, ids_ocupa
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;

  if ocupada_id is not null then
    ids_nuevo := public.contrato_identificadores(new.datos);
  end if;

  -- Carta ya sucedida por su propio Bloqueo: se deja guardar y se SALE sin tocar
  -- la parcela. Salir es la mitad importante del arreglo -- seguir habria hecho
  -- que el `update unidades` de mas abajo le devolviera la parcela a la Carta,
  -- robandosela al Bloqueo sin que nadie se enterara.
  if ocupada_id is not null
     and new.tipo in ('carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa')
     and ocupada_tipo = 'reserva_parcela'
     and ids_nuevo && ids_ocupa then
    return new;
  end if;

  traspaso_ok := new.tipo = 'reserva_parcela'
             and ocupada_tipo in ('carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa');

  if ocupada is not null and not traspaso_ok then
    raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
      using errcode = '23505';
  end if;

  -- LAW-51: el traspaso solo vale entre contratos del mismo comprador.
  if ocupada is not null and traspaso_ok then
    if coalesce(array_length(ids_nuevo, 1), 0) = 0
       or coalesce(array_length(ids_ocupa, 1), 0) = 0 then
      raise exception 'El traspaso de la parcela % de % no se puede comprobar: falta el pasaporte o el email del comprador en % o en el contrato que estás guardando. Complétalo y vuelve a guardar.',
        cod, proy, ocupada using errcode = '23514';
    end if;

    if not (ids_nuevo && ids_ocupa) then
      raise exception 'El traspaso de la parcela % de % no cuadra: % está a nombre de otro comprador. La parcela solo pasa de una Carta de Reserva a su Bloqueo si coincide el pasaporte o el email.',
        cod, proy, ocupada using errcode = '23514';
    end if;
  end if;

  update public.unidades u
     set contrato_id = new.id,
         estado = case
           -- vendida/cobrada solo las mueve el dinero (avanza_unidad_por_cobro)
           --  ninguna firma ni edicion de contrato las revierte.
           when u.estado in ('vendida','cobrada') then u.estado
           when u.estado = 'no_disponible' then u.estado
           -- bloqueada manual (sin RP firmado detras): protegida, igual que siempre.
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
           -- Contrato de Construccion: no mueve el estado de la parcela.
           when new.tipo = 'construccion' then u.estado
           -- cualquier otro caso (crear CR/RP, o firmar una CR) se queda en reservada.
           else 'reservada'
         end
   where u.proyecto = proy and u.codigo = cod;

  -- LAW-50: la Carta pasa a colgar del Bloqueo que se queda la parcela, para que
  -- Operaciones las enseñe como una sola venta. Solo si la Carta no tenia ya
  -- padre: sobrescribir un enlace puesto a mano seria decidir por el operador.
  if traspaso_ok and ocupada_id is not null then
    update public.contratos c
       set contrato_padre_id = new.id
     where c.id = ocupada_id and c.contrato_padre_id is null;
  end if;

  return new;
end $$;

-- El trigger trg_sincroniza_unidad ya existe y apunta a esta funcion por
-- nombre: no hay que recrearlo.
--
-- Comprobaciones despues de correrlo:
--   -- el guardarrail existe
--   select position('ids_nuevo' in prosrc) > 0 from pg_proc
--    where proname = 'sincroniza_unidad_contrato';
--   -- el caso real ya traspasado sigue cuadrando
--   select public.contrato_identificadores(datos) from public.contratos
--    where numero in ('CR00019','RP00040');
