-- Fix-forward sobre la consulta de deploy de hace un momento (capa 1), 3 hallazgos reales:
--
-- 1) [ALTA, Administración] Una parcela con Bloqueo de Parcela (suelo) + Contrato
--    de Construcción SEPARADO -patron real y normal en Lawang, confirmado contra
--    produccion: 6 CC reales tienen contrato_padre_id, ninguno lleva
--    parcela_codigo propio- nunca sumaba el cobro de los dos contratos juntos.
--    `avanza_unidad_por_cobro(cc_id)` ademas actualizaba 0 filas siempre, porque
--    `unidades.contrato_id` apunta al contrato de suelo, NUNCA al de
--    construccion (la CC no lleva parcela_codigo, sincroniza_unidad_contrato
--    nunca la vincula). Se resuelve via `contratos.contrato_padre_id` (ya
--    existente, 29-jul) al contrato "raiz" que unidades.contrato_id si conoce,
--    y se suma el cobro de la raiz + el de todos sus hijos.
--
-- 2) [ALTA, Desarrollo] El guardarraíl de moneda mezclada no cubria un recibi
--    repartido via `recibi_aplicaciones` cuyo PROPIO contrato_id (y moneda)
--    puede ser distinto del contrato de la factura a la que se aplica.
--    Se amplia a cubrir tambien esa via, sobre el mismo cluster raiz+hijos.
--
-- 3) [MEDIA, Legal] Un recibi contra una simple Carta de Reserva (sin Bloqueo de
--    Parcela firmado detras) saltaba directo a 'vendida' -- palabra con peso
--    contractual, publicada en el masterplan publico como "no disponible".
--    Contradice el propio orden que describio el owner (reservada -> bloqueada
--    -> vendida): el dinero avanza la escalera, no se la salta. Ahora hace
--    falta que la parcela ya este en 'bloqueada' (o mas alla) antes de que un
--    recibi la mueva a 'vendida'/'cobrada'.
create or replace function public.avanza_unidad_por_cobro(p_contrato_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_raiz_id uuid;
  v_cobrado numeric;
  v_mezcla  boolean;
begin
  if p_contrato_id is null then return; end if;

  -- el contrato "raiz" es el que unidades.contrato_id conoce de verdad: si
  -- p_contrato_id es un Contrato de Construccion, su padre; si no, el mismo.
  select coalesce(contrato_padre_id, id) into v_raiz_id
    from public.contratos where id = p_contrato_id;
  if v_raiz_id is null then return; end if;

  -- moneda mezclada en el cluster raiz+hijos, por cualquiera de las dos vias
  -- (recibi directo, o recibi repartido via recibi_aplicaciones) -- si la hay,
  -- no se puede fiar el 100% y se deja para que lo revise una persona.
  select exists (
    select 1 from public.facturas f
     where f.tipo = 'recibi' and not coalesce(f.anulada, false)
       and (f.contrato_id = v_raiz_id
            or f.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and f.moneda is distinct from (select u.moneda from public.unidades u where u.contrato_id = v_raiz_id)
    union all
    select 1 from public.recibi_aplicaciones ra
      join public.facturas r   on r.id = ra.recibi_id
      join public.facturas fac on fac.id = ra.factura_id
     where not coalesce(r.anulada, false) and not coalesce(fac.anulada, false)
       and (fac.contrato_id = v_raiz_id
            or fac.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and r.moneda is distinct from (select u.moneda from public.unidades u where u.contrato_id = v_raiz_id)
  ) into v_mezcla;
  if v_mezcla then return; end if;

  -- cobrado = raiz + todos sus hijos (normalmente 0 o 1 Contrato de Construccion)
  v_cobrado := coalesce(public.contrato_cobrado(v_raiz_id), 0);
  select v_cobrado + coalesce(sum(public.contrato_cobrado(hijo.id)), 0)
    into v_cobrado
    from public.contratos hijo
   where hijo.contrato_padre_id = v_raiz_id;

  update public.unidades u
     set estado = case
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           -- el dinero no se salta la escalera: hace falta el Bloqueo de
           -- Parcela firmado (bloqueada) antes de que un recibi avance nada.
           when u.estado not in ('bloqueada', 'vendida', 'cobrada') then u.estado
           when u.precio > 0 and v_cobrado >= u.precio then 'cobrada'
           when v_cobrado > 0 then 'vendida'
           else u.estado
         end
   where u.contrato_id = v_raiz_id;
end $$;
;
