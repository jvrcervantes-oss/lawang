/* INVESTOR DECK — tipologias de vivienda en vivo desde la intranet. 11-sep-2026.

   POR QUE. La seccion "The 3 Villa Typologies" del deck de Palm Field pintaba un
   array escrito a mano en el HTML. Ya habia derivado de la intranet: la intranet
   tiene CUATRO modelos asignados a Palm Field W5 (Dali, Dune, Dream y Temple) y el
   deck enseñaba tres, con un comentario que afirmaba que Temple "NO esta asignado a
   este proyecto" — falso desde que alguien lo asigno. Ademas la terraza de Dali
   (16 vs 17 m2) y la de Dune (29 vs 30) llevaban tiempo mal. Es la familia de fallo
   de «El dato tiene un dueño»: una copia a mano de un dato que tiene fuente.

   Hermano exacto de investor_deck_parcelas(text) (20260910025145): misma forma,
   misma acotacion, mismo grant.

   ── Revision previa hecha (Seguridad + Datos), CEO/flujos/revision_previa.md ──
   Lo que cazaron y como se pliega aqui:

   1. [Seguridad] Filtrar solo por `m.publicado and m.activo` NO es una decision de
      publicar: son los flags INTERNOS del catalogo de la intranet. Y con p_proyecto
      libre y la clave anon embebida en el HTML publico del deck, cualquiera podia
      pedir investor_deck_modelos('<otro proyecto>') y enumerar modelos y precios
      PACTADOS de toda la cartera. Se acota con el unico opt-in de publicacion que ya
      existe — unidades.publicado_investor_deck — en vez de inventar un segundo
      interruptor que derive del primero. Hoy solo Palm Field W5 lo tiene puesto
      (34/34 unidades); los otros 13 proyectos quedan cerrados, Sumba Hills incluido.

   2. [Datos] El `coalesce(mv.moneda, m.moneda)` que llevaba el plan era codigo muerto
      (modelos_villa.moneda es nullable pero con DEFAULT 'EUR', y las 32 filas vivas la
      tienen rellena) y, peor, podia sacar PRECIO de un nivel de la cascada y MONEDA de
      otro: en Temple, que hoy tiene precio_construccion NULL en modelos_villa, el precio
      se heredaba de `modelos` y la moneda se tomaba de `modelos_villa`. Hoy coinciden
      por suerte; con un modelo en IDR (Riverfront ya los tiene) eso publica un importe
      en rupias etiquetado EUR en una pagina que lee un inversor. Aqui precio y moneda
      salen SIEMPRE de la misma fila ganadora — un CTE, no dos coalesce independientes.

   3. [Datos] Cascada: este RPC resuelve el NIVEL 2 (modelos_villa, el precio pactado
      para ESTE proyecto) con herencia del nivel 1 (modelos) cuando el 2 es NULL. No
      mira el nivel 3 (unidades.precio_construccion) a proposito: un deck enseña la
      tipologia, no lo pactado en una unidad concreta.
      ⚠️ catalogo_publico(), que alimenta /modelo/<slug> en la web publica, resuelve
      SOLO el nivel 1. Son dos superficies publicas que pueden dar cifras distintas al
      mismo comprador. En Palm Field hoy coinciden los tres precios, asi que esto nace
      sin sintoma; en Sumba Hills ya divergen (Dali 54.000 en modelos_villa vs 48.000 en
      catalogo). Cual de los dos es la fuente publica unica es decision del owner, no se
      arregla de tapadillo aqui: queda como pendiente (LAW, contexto/pendientes.md).

   4. Nunca se devuelve `notas` — ni la de `modelos` ni la de `modelos_villa`. Ambas son
      internas del equipo, y catalogo_publico() ya las excluye a proposito.

   5. Tampoco se devuelve `renders_pendientes`: la flag MIENTE hoy (Temple la tiene en
      false y no existe assets/img/buildings/temple/ en disco). El deck decide ese estado
      por que el asset EXISTA (fallback onerror en la imagen), que es mecanico y cierra
      la clase entera, en vez de por una flag o por una lista de slugs a mano — que es
      exactamente el patron que provoco los 404 del 10-sep-2026.

   No toca ninguna fila. No toca unidades, contratos ni el flujo de reserva. */

create or replace function public.investor_deck_modelos(p_proyecto text)
returns table(
  slug        text,
  nombre      text,
  dormitorios integer,
  banos       integer,
  villa_m2    numeric,
  terraza_m2  numeric,
  precio      numeric,
  moneda      text,
  orden       integer
)
language sql
security definer
stable
set search_path = public
as $$
  -- `gana` elige de que fila sale el precio, y la moneda viaja CON el, nunca aparte.
  with base as (
    select m.slug, m.nombre, m.dormitorios, m.banos, m.villa_m2, m.terraza_m2, m.orden,
           (mv.precio_construccion is not null) as gana_proyecto,
           mv.precio_construccion as precio_proyecto,
           mv.moneda              as moneda_proyecto,
           m.precio_construccion  as precio_catalogo,
           m.moneda               as moneda_catalogo
      from public.modelos_villa mv
      join public.modelos m on m.id = mv.modelo_id
     where mv.proyecto = p_proyecto
       and m.publicado
       and m.activo
       -- opt-in de publicacion: solo proyectos que el owner ha abierto al data room.
       and exists (
             select 1 from public.unidades u
              where u.proyecto = mv.proyecto
                and u.publicado_investor_deck
           )
  )
  select slug, nombre, dormitorios, banos, villa_m2, terraza_m2,
         case when gana_proyecto then precio_proyecto else precio_catalogo end as precio,
         case when gana_proyecto then coalesce(moneda_proyecto, moneda_catalogo)
              else moneda_catalogo end                                        as moneda,
         orden
    from base
   order by orden nulls last, nombre;
$$;

revoke all on function public.investor_deck_modelos(text) from public;
grant execute on function public.investor_deck_modelos(text) to anon, authenticated;

comment on function public.investor_deck_modelos is
  'Lectura publica y acotada del catalogo de modelos ASIGNADOS a un proyecto, para el data room de inversores. Solo proyectos con unidades publicado_investor_deck=true (hoy: Palm Field W5). Precio = nivel 2 de la cascada (modelos_villa) heredando del nivel 1 (modelos) cuando es NULL, y la moneda sale SIEMPRE de la misma fila que el precio. Nunca notas ni renders_pendientes.';
