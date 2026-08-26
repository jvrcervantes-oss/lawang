-- Una parcela reservada por una Carta de Reserva puede pasar a su Bloqueo de
-- Parcela — 14-ago-2026, petición del owner (caso real: A4 de Bonian Village).
--
-- SÍNTOMA: el cliente reserva con una Carta de Reserva, decide comprar, y al
-- emitirle el Bloqueo de Parcela el guardado muere con
--   La parcela A4 de Bonian Village ya está asignada al contrato CR000xx
-- Es decir: el paso NORMAL de una venta estaba prohibido. La secuencia real,
-- la que describe el propio TEMPLATES de app.html, es "se reserva, se bloquea
-- la parcela y se firma la obra" — y el segundo paso no podía darse sin ir a
-- mano a /intranet/proyectos/ a soltar la parcela primero.
--
-- CAUSA: la comprobación de ocupación miraba SOLO si había otro contrato, no
-- CUÁL. Cualquier contrato distinto del que se guarda bloqueaba, incluida la
-- Carta de Reserva que precede a este mismo Bloqueo.
--
-- QUÉ CAMBIA, y nada más: se permite el traspaso cuando el que entra es un
-- Bloqueo de Parcela y el que ocupa es una Carta de Reserva (las tres
-- variantes: corta, ampliada y Hak Sewa). Todo lo demás sigue bloqueado igual
-- que hasta hoy — dos Bloqueos sobre la misma parcela, o una Carta sobre una
-- parcela que ya tiene Bloqueo, siguen dando el mismo error.
--
-- LO QUE NO HACE, a propósito: no comprueba que el comprador sea el mismo. El
-- nombre es texto libre y compararlo por igualdad daría falsos bloqueos por una
-- tilde o un segundo apellido, que es justo la fricción que se viene a quitar.
-- Si se quiere ese guardarraíl, el sitio es `contrato_compradores` (la relación
-- real con `clients`), no el nombre — y es una decisión aparte.
--
-- ✅ COMPROBADO ANTES DE ESCRIBIR ESTO (14-ago-2026): se sacó el `prosrc` de
-- producción y se comparó con estado_unidad_por_tipo_y_cobro.sql — misma lógica
-- línea por línea. Dos diferencias, las dos de forma: producción NO tiene
-- tildes ni comentarios (se perdieron al aplicarla en su día). Por eso el
-- mensaje de la excepción va aquí SIN tilde, "ya esta asignada", igual que el
-- que sale hoy: no toca un texto que nadie ha pedido cambiar. app.html lo
-- reconoce con /ya est[aá] asignada/i, así que le vale cualquiera de los dos —
-- pero mejor no depender de eso sin motivo.

create or replace function public.sincroniza_unidad_contrato()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  cod          text := nullif(btrim(new.datos->'fields'->>'parcela_codigo'), '');
  proy         text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  cod_ant      text;
  ocupada      text;
  ocupada_tipo text;
  traspaso_ok  boolean;
begin
  if tg_op = 'UPDATE' then
    cod_ant := nullif(btrim(old.datos->'fields'->>'parcela_codigo'), '');
    if cod_ant is distinct from cod then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id;
    end if;
  end if;

  if cod is null or proy is null then return new; end if;

  -- ahora importa QUIEN ocupa, no solo que haya alguien
  select c.numero, c.tipo into ocupada, ocupada_tipo
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;

  traspaso_ok := new.tipo = 'reserva_parcela'
             and ocupada_tipo in ('carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa');

  if ocupada is not null and not traspaso_ok then
    raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
      using errcode = '23505';
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

  return new;
end $$;

-- El trigger trg_sincroniza_unidad ya existe y apunta a esta función por
-- nombre: no hay que recrearlo.
--
-- Comprobación después de correrlo, con el caso real:
--   select u.codigo, u.estado, c.numero, c.tipo
--     from public.unidades u left join public.contratos c on c.id = u.contrato_id
--    where u.proyecto = 'Bonian Village' and u.codigo = 'A4';
-- Antes del Bloqueo debe salir la Carta (CR…); después de guardarlo, el RP…
