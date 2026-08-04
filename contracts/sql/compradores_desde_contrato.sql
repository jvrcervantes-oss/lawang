-- ============================================================================
-- La ficha del comprador la crea la BASE, no la aplicación — 4-ago-2026
-- ----------------------------------------------------------------------------
-- PREGUNTA DEL OWNER: «¿todos los contratos crean usuarios en compradores?».
-- Medido sobre los 32 contratos de producción: NO. Faltaban 5 enlaces en 5
-- contratos (RP00012 ×2, CC00007, RP00016, CC00008), y de los 5, tres personas
-- no tenían ni ficha.
--
-- Es la SEGUNDA vez que se mide lo mismo (31-jul y 4-ago), así que la regla
-- sube un peldaño de la escalera: deja de vivir en el JavaScript de una
-- pantalla y pasa a ser un disparador de la base. El motivo es el mismo que ya
-- se escribió para `vinculo_contrato_unidad.sql` el 31-jul: a `contratos` le
-- escriben tres sitios distintos —la app, la función de firma y cualquier
-- corrección por SQL— y una regla que vive en uno de los tres no se cumple
-- desde los otros dos.
--
-- POR QUÉ FALLABA. Tres causas distintas, y solo una era la que estaba escrita:
--   1. `clients.email` es UNIQUE y una familia comparte correo. Mª Amparo
--      (CC00007 y RP00016) da el mismo email que su marido Juan Ramón, que ya
--      tenía ficha: el insert moría con violación de clave única y el aviso se
--      iba con el toast. NO era «se guardó antes de que existiera el alta».
--      → Ahora, si el correo ya es de otra persona, la ficha se crea SIN correo:
--        a quien trae pasaporte lo identifica el pasaporte, y perder el correo
--        de la ficha es infinitamente menos grave que no tener ficha.
--   2. Contratos guardados antes del 28-jul (RP00012) nunca pasaron por el alta,
--      y nadie reabre un contrato viejo para reguardarlo.
--      → Ahora hay una función que se puede pasar sobre lo ya guardado.
--   3. CC00008 tenía un cuarto adquiriente que el bug de roles ≤3 se comió, y el
--      contrato está BLOQUEADO: reguardarlo no es una opción.
--      → La función se llama por id, sin tocar el contrato. Un documento firmado
--        no se altera para arreglar su índice de personas.
--
-- QUÉ NO HACE, A PROPÓSITO:
--   · Sin pasaporte NI email no crea ficha. Un "cliente" sin identificador se
--     duplica en cuanto alguien teclee el nombre distinto, y limpiar eso después
--     cuesta más que no crearlo. Hoy son 3: CC00004, CR00006 y RP00022.
--   · No enriquece fichas existentes. Si la persona ya está, se enlaza y punto:
--     pisar un dato que alguien corrigió a mano desde Compradores con el que
--     lleva el contrato viejo es perder trabajo, no ganarlo.
--   · No aborta el guardado si algo va mal (ver el disparador, abajo).
-- ============================================================================

create or replace function public.sincronizar_compradores(p_contrato uuid)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_datos  jsonb;
  v_gente  jsonb;
  p        jsonb;
  v_nombre text; v_rol text; v_pas text; v_mail text;
  v_client uuid;
  v_altas int := 0; v_enlaces int := 0;
  v_sin_id text[] := '{}';
  v_sin_mail text[] := '{}';
begin
  select datos into v_datos from contratos where id = p_contrato;
  if v_datos is null then return jsonb_build_object('error', 'contrato inexistente o sin datos'); end if;

  -- ⚠️ Los campos del contrato viven en `datos->'fields'`, NO en la raíz de
  -- `datos`. En la raíz solo están compradores, hitos, overrides, clauses,
  -- annexes y design. Consultar `datos->>'adq1_nombre'` devuelve null SIN error
  -- y parece un resultado válido: así se midió un hueco en vez de cuatro.
  --
  -- Y `datos->'compradores'` son los adquirientes ADICIONALES: el Adquiriente I
  -- vive siempre en `adq1_*`, y compradores[0] es el II. La primera versión de
  -- esto (28-jul) trataba compradores[0] como el I y en un contrato a dos
  -- nombres daba de alta al segundo con la etiqueta del primero.
  v_gente := jsonb_build_array(jsonb_build_object(
      'rol','adquiriente_1',
      'nombre',       v_datos->'fields'->>'adq1_nombre',
      'pasaporte',    v_datos->'fields'->>'adq1_pasaporte',
      'email',        v_datos->'fields'->>'adq1_email',
      'telefono',     v_datos->'fields'->>'adq1_telefono',
      'nacionalidad', v_datos->'fields'->>'adq1_nacionalidad',
      'domicilio',    v_datos->'fields'->>'adq1_domicilio'))
    || coalesce((
      select jsonb_agg(jsonb_build_object(
               'rol','adquiriente_' || (ord + 1),
               'nombre', e->>'nombre', 'pasaporte', e->>'pasaporte', 'email', e->>'email',
               'telefono', e->>'telefono', 'nacionalidad', e->>'nacionalidad',
               'domicilio', e->>'domicilio') order by ord)
      from jsonb_array_elements(
             case when jsonb_typeof(v_datos->'compradores') = 'array'
                  then v_datos->'compradores' else '[]'::jsonb end) with ordinality t(e, ord)
      -- Por encima del noveno no se inventa un rol: el CHECK solo admite
      -- adquiriente_1..9 y la clave (contrato_id, rol) chocaría, pisando al
      -- anterior en silencio. Se queda fuera y se dice.
      where ord + 1 <= 9), '[]'::jsonb);

  for p in select value from jsonb_array_elements(v_gente) loop
    v_nombre := btrim(coalesce(p->>'nombre',''));
    continue when v_nombre = '';
    v_rol  := p->>'rol';
    v_pas  := nullif(btrim(coalesce(p->>'pasaporte','')), '');
    v_mail := lower(nullif(btrim(coalesce(p->>'email','')), ''));

    if v_pas is null and v_mail is null then
      v_sin_id := v_sin_id || v_nombre;
      continue;
    end if;

    -- Identidad: manda el PASAPORTE. Si lo trae y no casa con nadie, es una
    -- persona nueva aunque su correo sea el de otro — que es justo el caso del
    -- matrimonio que comparte email. Solo sin pasaporte se busca por correo.
    v_client := null;
    if v_pas is not null then
      select id into v_client from clients
       where lower(btrim(passport_number)) = lower(v_pas) limit 1;
    elsif v_mail is not null then
      select id into v_client from clients where lower(email) = v_mail limit 1;
    end if;

    if v_client is null then
      if v_mail is not null and exists (select 1 from clients where lower(email) = v_mail) then
        v_sin_mail := v_sin_mail || v_nombre;
        v_mail := null;   -- UNIQUE(email): antes que no crear la ficha, se crea sin correo
      end if;
      insert into clients (full_name, email, phone, nationality, passport_number, address, kyc_status)
      values (v_nombre, v_mail,
              nullif(btrim(coalesce(p->>'telefono','')), ''),
              nullif(btrim(coalesce(p->>'nacionalidad','')), ''),
              v_pas,
              nullif(btrim(coalesce(p->>'domicilio','')), ''),
              'pending')
      returning id into v_client;
      v_altas := v_altas + 1;
    end if;

    insert into contrato_compradores (contrato_id, client_id, rol)
    values (p_contrato, v_client, v_rol)
    on conflict (contrato_id, rol) do update set client_id = excluded.client_id;
    v_enlaces := v_enlaces + 1;
  end loop;

  return jsonb_build_object('altas', v_altas, 'enlaces', v_enlaces,
                            'sin_identificador', to_jsonb(v_sin_id),
                            'ficha_sin_correo',  to_jsonb(v_sin_mail));
end $$;

comment on function public.sincronizar_compradores(uuid) is
  'Crea/enlaza las fichas de comprador de un contrato leyendo datos->fields->adq1_* y datos->compradores. Idempotente: se puede repasar sobre lo ya guardado.';

-- ── el disparador ───────────────────────────────────────────────────────────
-- NO aborta el guardado. El de la unidad (`trg_sincroniza_unidad`) sí lo hace, y
-- está bien: allí lo que evita es vender dos veces la misma parcela. Aquí, en
-- cambio, abortar significaría que un operador no puede guardar un CONTRATO por
-- culpa del índice de personas — el documento importa más que el índice.
-- El fallo no se pierde: queda de warning en el log de Postgres y, sobre todo,
-- Operaciones ya pinta «Falta ficha» en la propia lista, que es donde alguien
-- lo va a ver de verdad.
create or replace function public.trg_sincronizar_compradores()
returns trigger language plpgsql set search_path = public as $$
begin
  begin
    perform public.sincronizar_compradores(new.id);
  exception when others then
    raise warning 'sincronizar_compradores(%) no pudo completarse: %', new.id, sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists trg_compradores_desde_datos on public.contratos;
create trigger trg_compradores_desde_datos
after insert or update of datos on public.contratos
for each row execute function public.trg_sincronizar_compradores();

-- ═══════════════════════════════════════════════════════════════
-- REPASO DE LO YA GUARDADO
-- Es lo que nunca hubo: el alta corría al guardar y nada miraba hacia atrás.
-- Idempotente — no duplica nada al repetirlo.
-- ═══════════════════════════════════════════════════════════════
-- select numero, public.sincronizar_compradores(id) from public.contratos order by numero;

-- ═══════════════════════════════════════════════════════════════
-- COMPROBACIÓN — cuántos contratos nombran a más gente de la que tiene ficha
-- ═══════════════════════════════════════════════════════════════
-- Debe devolver solo los que no traen ni pasaporte ni email (hoy: CC00004,
-- CR00006, RP00022). Cualquier otro es un hueco de verdad.
with ct as (
  select c.numero,
         (case when nullif(btrim(c.datos->'fields'->>'adq1_nombre'),'') is null then 0 else 1 end)
         + coalesce((select count(*) from jsonb_array_elements(
              case when jsonb_typeof(c.datos->'compradores')='array' then c.datos->'compradores' else '[]'::jsonb end) e
              where nullif(btrim(e->>'nombre'),'') is not null), 0) as nombrados,
         (select count(*) from public.contrato_compradores cc where cc.contrato_id = c.id) as fichas
  from public.contratos c
)
select numero, nombrados, fichas from ct where nombrados > fichas order by numero;
