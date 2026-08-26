-- LAW-41(2) — un recibí solo puede saldar facturas DE SU MISMO COMPRADOR
-- 19-ago-2026. Cierra el hueco por el que REC00019 (1.000 €, Jorge Miguel
-- Domingo Berenguer, CR00020) acabó aplicado a INV00001, una factura de
-- Carmen Ribera Valdes. El único check del bucle de guardar_recibi() era
-- "existe, es tipo factura y no está anulada": nada miraba de QUIÉN era.
--
-- Por qué NO se exige "mismo contrato": aplicar un recibí a la factura de
-- OTRO contrato del mismo comprador es un caso de uso real y vivo — REC00020
-- (Eduardo Cuellar) cuelga de CC00026 y salda INV00015, que es de RP00047.
-- Cruzar contrato entre padre e hija sí; cruzar comprador no.
--
-- La identidad se compara con `contrato_identificadores` (pasaporte + email
-- del jsonb), la MISMA función con la que LAW-51 decide si dos contratos son
-- del mismo comprador al traspasar una parcela. Un solo criterio de identidad
-- en toda la suite: si mañana cambia, cambia en un sitio.
--
-- Decisión heredada de LAW-51 (owner): si falta identidad en cualquiera de los
-- dos lados, SE BLOQUEA. `&&` sobre un array vacío da false, así que sale
-- gratis y no hay que escribirlo aparte.
--
-- Efecto colateral buscado: una factura sin `contrato_id` no cuelga de ningún
-- comprador, así que deja de poder recibir dinero. Son exactamente las 3 de
-- LAW-38 (INV00001/2/3, 60.000 €, clientes que no tienen contrato en el
-- sistema). Hasta que alguien les dé contrato, no vuelven a contaminar cobros.

-- ── el criterio, UNA sola vez ────────────────────────────────────────────────
-- security definer a propósito: un agente puede saldar la factura de un
-- contrato que firmó otro agente (por eso existen contratos_equipo/
-- facturas_equipo), y la RLS por autor no le dejaría leerlo. Devuelve un
-- booleano, no datos del contrato ajeno.
create or replace function public.contratos_mismo_comprador(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- El mismo contrato es trivialmente el mismo comprador, y ese caso va PRIMERO
  -- a proposito: hay contratos sin identidad utilizable (RP00043, 165.800 EUR,
  -- con el email metido en el campo del nombre; CO00004) y exigirles identidad
  -- les impediria cobrar su PROPIA factura. La decision de LAW-51 —si falta
  -- identidad en cualquiera de los dos lados, se bloquea— es para comparar dos
  -- registros DISTINTOS; aqui solo aplica cuando de verdad son dos.
  select p_a is not null and p_b is not null and (
    p_a = p_b or coalesce((
      select public.contrato_identificadores(a.datos)
          && public.contrato_identificadores(b.datos)
        from public.contratos a, public.contratos b
       where a.id = p_a and b.id = p_b
    ), false)
  );
$$;

revoke all on function public.contratos_mismo_comprador(uuid, uuid) from public, anon;
grant execute on function public.contratos_mismo_comprador(uuid, uuid) to authenticated;

-- ── contratos_del_mismo_comprador: MUDADA, no vive aquí ───────────────────────
-- Este fichero la creó el 19-ago (versión que escaneaba `datos` jsonb de TODA
-- la tabla — el mismo patrón que provocó el 500/timeout de contratos jsonb).
-- El 24-ago (auditoría de Desarrollo) se sustituyó por una versión que hace
-- JOIN por `contrato_compradores` en vez de leer el blob: la definición viva
-- está en `facturas/sql/contratos_del_mismo_comprador_rapido.sql`, que es el
-- dueño real desde entonces. Se deja fuera de aquí a propósito — dos
-- `create or replace` de la misma función en dos ficheros es la trampa que
-- este comentario existe para evitar: si algún día se retoca `guardar_recibi`
-- y se reaplica este fichero entero, NO debe poder resucitar la versión lenta.

-- ── guardar_recibi: MUDADA, no vive aquí ──────────────────────────────────────
-- Igual que arriba: esta era la versión de 19-ago (el check de "mismo
-- comprador" sin más). LAW-71 (mismo día, más tarde) le añadió el salto
-- auditable de super_admin sobre factura huérfana / de otro comprador — la
-- definición viva está en `contracts/sql/super_admin_poderes.sql`. Reaplicar
-- este fichero entero NO debe poder borrar ese poder de super_admin.
