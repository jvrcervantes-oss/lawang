-- Candado de parcela (26-sep-2026, owner: «solo el candado, pequeño», LAW-133).
-- Por qué: el 12-sep A7 de Bonian se quitó de RP00045 con la ✕ del chip + Guardar mientras su Carta
-- hija CR00022, FIRMADA, la seguía nombrando; quedó «disponible» 24 min y la cogió otro contrato.
-- Soltar y volver a ocupar eran dos transacciones sin relación. El traspaso completo en un paso se
-- aparcó (revisión previa #112: un contrato firmado no puede cambiar su parcela sin contradecir su PDF
-- — decisión de Legal —, re-colgar Cartas se salta el candado de comisiones en DEFINER). Esto cierra
-- solo la puerta que causó el incidente.
--
-- Qué hace: en `sincroniza_unidad_contrato`, antes del UPDATE que suelta las parcelas que salen,
-- rechaza (23514, mensaje para la pantalla) soltar una parcela si:
--   · la nombra una Carta hija viva y firmada (contrato_padre_id = este, bloqueado, sin liberar), o
--   · la unidad está vendida o cobrada.
-- Los traspasos legítimos, raros, los hace el estudio con el OK del owner poniendo en la transacción
-- `set_config('app.via_traspaso_estudio', 'on', true)` (misma técnica que app.via_libera_reserva).
-- No afecta a: libera_reserva / cron de reservas vencidas (salen al principio por liberado_en), traspaso
-- automático Carta→Bloqueo (no quita códigos), guardados que no cambian parcelas.
-- Hueco conocido y anotado (LAW-133): el formulario de unidad y el importador CSV escriben directamente
-- en `unidades` y no pasan por aquí.
-- Parche con marca sobre la definición VIVA (pg_get_functiondef; el .sql del repo está desfasado),
-- idempotente, y raise si la marca no está. Probado el 26-sep en transacción revertida: RP00159 no
-- puede soltar B3 (la nombra CP00002 firmada); guardar sin tocar parcelas OK; RP00062 (sin
-- protección) suelta D2; con app.via_traspaso_estudio B3 queda libre.

do $do$
declare
  def   text := pg_get_functiondef('public.sincroniza_unidad_contrato'::regproc);
  marca text := $m$      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id
         and (u.proyecto is distinct from proy or not (u.codigo = any (cods)));$m$;
  candado text := $c$      if coalesce(current_setting('app.via_traspaso_estudio', true), '') <> 'on' then
        select u.codigo, cr.numero, u.estado into cod, ocupada, estado_tr
          from public.unidades u
          left join public.contratos cr
            on cr.contrato_padre_id = new.id and cr.id <> new.id
           and cr.liberado_en is null and coalesce(cr.bloqueado, false)
           and u.codigo = any (select btrim(x) from unnest(string_to_array(coalesce(cr.datos->'fields'->>'parcela_codigo', ''), ',')) x)
         where u.contrato_id = new.id
           and (u.proyecto is distinct from proy or not (u.codigo = any (cods)))
           and (u.estado in ('vendida', 'cobrada') or cr.id is not null)
         limit 1;
        if cod is not null then
          if ocupada is not null then
            raise exception 'La parcela % de % no se puede quitar de %: la nombra la Carta de Reserva firmada %. Moverla es un traspaso: pídeselo a administración.',
              cod, proy_ant, new.numero, ocupada using errcode = '23514';
          end if;
          raise exception 'La parcela % de % no se puede quitar de %: está %. Pídeselo a administración.',
            cod, proy_ant, new.numero, estado_tr using errcode = '23514';
        end if;
        cod := null; ocupada := null; estado_tr := null;
      end if;
$c$;
begin
  if position('app.via_traspaso_estudio' in def) > 0 then
    return;
  end if;
  if position(marca in def) = 0 then
    raise exception 'sincroniza_unidad_contrato: no encuentro la marca del UPDATE que suelta parcelas';
  end if;
  execute replace(def, marca, candado || marca);
end $do$;
