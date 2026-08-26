/* El precio de una unidad es suelo + construcción. `unidades.precio` guarda el
   total, pero un CSV que trae «Land» y «Villa» y ninguna columna de total lo deja
   NULL — y entonces toda vista que sume `precio` enseña 0 aunque la unidad tenga
   precio de sobra.

   Medido el 26-ago-2026: 45 unidades en 4 proyectos (Riverfront I y II, Palm
   Field W5, Mejan Village S7) con suelo y/o construcción y sin total. Palm Field
   salía como «0,00 EUR» con 34 parcelas valoradas — el owner lo vio en el móvil.
   Y `pct_cobrado` también era NULL para esas 45, porque divide entre `u.precio`.

   Se deriva AQUÍ, en la vista, y no en cada pantalla: es un dato calculado y su
   dueño es la base. Solo se deriva cuando el total NO está guardado — un precio
   puesto a mano (un descuento, un precio pactado distinto de la suma) manda
   siempre sobre sus partes.

   `precio_guardado` va AL FINAL porque `create or replace view` no deja meter una
   columna en medio, y expone el valor CRUDO para quien tenga que editarlo: el
   formulario de la unidad debe prefijar lo que hay en la tabla, no el derivado, o
   al guardar materializaría en silencio un total que nadie tecleó. */
create or replace view public.unidades_estado as
select u.id, u.codigo, u.proyecto, u.tipo, u.superficie_m2,
       coalesce(u.precio,
                nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)
       ) as precio,
       u.moneda, u.estado, u.contrato_id, u.notas, u.created_at,
       u.precio_suelo, u.precio_construccion, u.modelo,
       u.obra_fase, u.obra_fecha_entrega, u.obra_actualizado,
       c.numero as contrato_numero,
       c.comprador_nombre,
       c.bloqueado as contrato_firmado,
       coalesce(unidad_parte_cobrada(u.id), 0::numeric) as facturado,
       case
         when coalesce(u.precio,
                       nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)
              ) > 0::numeric
         then round(coalesce(unidad_parte_cobrada(u.id), 0::numeric)
                    / coalesce(u.precio,
                               nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0))
                    * 100::numeric, 1)
         else null::numeric
       end as pct_cobrado,
       u.fase_masterplan, u.zona_masterplan,
       u.precio as precio_guardado
  from unidades u
  left join contratos c on c.id = u.contrato_id;;
