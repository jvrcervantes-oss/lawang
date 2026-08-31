-- ════════════════════════════════════════════════════════════════════════════
-- LOS TIPOS DE CONTRATO, DECLARADOS UNA SOLA VEZ — 17-ago-2026 (auditoría, LAW-48)
-- ════════════════════════════════════════════════════════════════════════════
-- POR QUÉ EXISTE. Dar de alta un tipo de contrato exigía tocar CUATRO sitios:
--
--   1. `CONTRACT_TIPO` en contracts/app.html          (qué plantilla es cada tipo)
--   2. `TIPO_PREFIX`   en contracts/app.html          (su serie: RP, CC, CR…)
--   3. `set_contrato_numero()`                        (la misma serie, en Postgres)
--   4. `contratos_tipo_check`                         (los valores que la columna admite)
--   5. `LW_TIPO_CONTRATO` en assets/vocabulario.js    (cómo se llama en pantalla)
--
-- Y ha fallado dos veces, cada una por un sitio distinto:
--   · 28-jul-2026 — un estado nuevo sin su CHECK: error ilegible al guardar.
--   · 14-ago-2026 — 'poa' estaba en la app y en la numeración pero NO en el
--     CHECK: guardar un Poder Notarial daba 400 y, de rebote, el campo «Nº de
--     contrato» no se rellenaba nunca (el número lo pone el trigger AL insertar,
--     y el insert no llegaba a ocurrir).
--   · Y el quinto no rompe: se limita a enseñar la clave cruda de la base de
--     datos. Así salieron seis contratos reales con jerga en pantalla.
--
-- La regla «al añadir un tipo, toca los cuatro» estaba escrita dos veces y falló
-- dos veces. Por la escalera de aprendizaje del estudio, eso significa que le
-- toca GUARDARRAÍL, no una tercera redacción más larga.
--
-- QUÉ HACE ESTE FICHERO. Declara la lista UNA vez, en `tipos`, y deriva de ella
-- los dos sitios de la base de datos: la restricción CHECK y la función de
-- numeración. Los puntos 3 y 4 dejan de poder separarse porque dejan de ser dos
-- listas. Quedan dos: esta y la de la app — y entre las dos vigila
-- `contracts/listas.test.js`, que corre en el gate de push y compara este mismo
-- fichero contra app.html y vocabulario.js.
--
-- Añadir un tipo, a partir de hoy:
--   a) una fila más en `tipos`, aquí abajo;
--   b) correr este fichero en Supabase (es idempotente: se puede correr siempre);
--   c) su entrada en CONTRACT_TIPO/TIPO_PREFIX de app.html y en vocabulario.js.
--   El test dice si te falta alguna de las tres, y por su nombre.
--
-- ES IDEMPOTENTE Y NO DESTRUYE NADA:
--   · va en un solo bloque DO, o sea una transacción: si algo falla, la tabla NO
--     se queda sin restricción (que es el riesgo real de un DROP + ADD);
--   · antes de tocar el CHECK comprueba que TODOS los valores que ya existen en
--     `contratos.tipo` están en la lista, y aborta nombrando el que falte. Sin
--     eso, una lista incompleta convertiría filas reales en filas que ya no
--     pueden ni editarse;
--   · `create sequence if not exists`: nunca reinicia una serie viva. Reiniciar
--     una serie de numeración de contratos significa emitir dos documentos con el
--     mismo número.
-- ════════════════════════════════════════════════════════════════════════════

do $$
declare
  -- ── LA LISTA. tipo · prefijo de la serie · nombre de la secuencia ──────────
  -- La secuencia va explícita y no derivada del prefijo a propósito: la de 'poa'
  -- se llama `contratos_poa_seq` y no `contratos_pa_seq`, porque se creó el
  -- 10-ago con el nombre del tipo en vez del de la serie. Derivarla del prefijo
  -- crearía una secuencia NUEVA y volvería a empezar por PA00001, encima de
  -- números ya emitidos.
  tipos text[][] := array[
    ['reserva_parcela',        'RP', 'public.contratos_rp_seq'],
    ['construccion',           'CC', 'public.contratos_cc_seq'],
    ['contrato_general',       'CG', 'public.contratos_cg_seq'],
    ['commercial_offer',       'CO', 'public.contratos_co_seq'],
    ['carta_reserva',          'CR', 'public.contratos_cr_seq'],
    ['carta_reserva_ampliada', 'CA', 'public.contratos_ca_seq'],
    ['acuerdo_comercial',      'AC', 'public.contratos_ac_seq'],
    ['protocolo_operativo',    'PO', 'public.contratos_po_seq'],
    ['ppjb_bonian',            'PB', 'public.contratos_pb_seq'],
    ['ppjb_bonian_c2',         'C2', 'public.contratos_c2_seq'],
    ['hak_sewa_notario',       'HS', 'public.contratos_hs_seq'],
    ['carta_reserva_hak_sewa', 'CH', 'public.contratos_ch_seq'],
    ['poa',                    'PA', 'public.contratos_poa_seq'],
    -- Mismo prefijo/secuencia que 'construccion' (28-ago-2026): es esa misma
    -- plantilla, solo que con el texto negociado de CC00014 (Timon Taeke van
    -- den Bosch). Ya aplicado en vivo vía MCP ese mismo día — esta fila solo
    -- pone al día el generador para que vuelva a coincidir con producción
    -- (verificado contra prosrc/pg_get_constraintdef antes de añadirla).
    ['cc00014_timon',          'CC', 'public.contratos_cc_seq']
  ];
  i          int;
  n          int := array_length(tipos, 1);
  huerfano   text;
  lista_sql  text := '';
  casos_sql  text := '';
  cuerpo     text;
begin
  -- ── 1. Ninguna fila existente se queda fuera ────────────────────────────
  select c.tipo into huerfano
    from public.contratos c
   where c.tipo is not null
     and not (c.tipo = any (array(select tipos[k][1] from generate_subscripts(tipos,1) k)))
   limit 1;
  if huerfano is not null then
    raise exception
      'El tipo "%" existe en filas de `contratos` y NO está en la lista de este fichero. '
      'Añádelo antes de seguir: si no, esas filas dejarían de poder editarse.', huerfano;
  end if;

  -- ── 2. Las secuencias que falten (nunca las que ya están) ───────────────
  for i in 1..n loop
    execute format('create sequence if not exists %s', tipos[i][3]);
  end loop;

  -- ── 3. La restricción CHECK, generada de la lista ────────────────────────
  for i in 1..n loop
    lista_sql := lista_sql || case when i > 1 then ', ' else '' end
                 || quote_literal(tipos[i][1]) || '::text';
  end loop;

  if exists (select 1 from pg_constraint
              where conrelid = 'public.contratos'::regclass
                and conname  = 'contratos_tipo_check') then
    execute 'alter table public.contratos drop constraint contratos_tipo_check';
  end if;
  execute 'alter table public.contratos add constraint contratos_tipo_check '
          || 'check ((tipo = any (array[' || lista_sql || '])))';

  -- ── 4. La numeración, generada de la MISMA lista ─────────────────────────
  -- `if new.numero is not null then return new` se conserva tal cual: es lo que
  -- permite insertar con un número puesto a mano sin quemar uno de la serie
  -- (probar sin ensuciar, ver contexto/suite_lawang.md).
  for i in 1..n loop
    casos_sql := casos_sql || format(
      E'    when %L then prefix := %L; seqname := %L;\n',
      tipos[i][1], tipos[i][2], tipos[i][3]);
  end loop;

  cuerpo := E'declare\n  n bigint;\n  prefix text;\n  seqname text;\nbegin\n'
         || E'  if new.numero is not null then\n    return new;\n  end if;\n'
         || E'  case new.tipo\n' || casos_sql
         || E'    else raise exception ''Tipo de contrato sin numeracion definida: %'', new.tipo;\n'
         || E'  end case;\n  n := nextval(seqname);\n'
         || E'  new.numero := prefix || lpad(n::text, 5, ''0'');\n  return new;\nend;';

  -- SIN `security definer`, y verificado contra la función que hay en producción
  -- (`prosecdef = false`, 17-ago-2026) antes de escribir esto: regenerar un
  -- trigger es la clase de sitio donde se cuela una elevación de privilegio que
  -- nadie pidió, porque el que la escribe copia el `definer` de la función de al
  -- lado. Aquí no hace falta: el trigger corre dentro del INSERT de quien ya
  -- tiene permiso para insertar, y solo llama a `nextval` de sus propias series.
  -- `search_path to ''` sí se conserva: es lo que impide que un esquema en el
  -- camino de búsqueda le cambie a qué `nextval` está llamando.
  execute 'create or replace function public.set_contrato_numero() returns trigger '
       || 'language plpgsql set search_path to '''' as $f$' || cuerpo || '$f$';

  raise notice 'tipos_de_contrato: % tipos · CHECK y set_contrato_numero() regenerados de la misma lista', n;
end $$;

-- ── Comprobación (la del catálogo, no la de que alguien lo corriera) ─────────
-- Un `.sql` no está aplicado hasta que se consulta el catálogo:
--
--   select pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'public.contratos'::regclass and conname = 'contratos_tipo_check';
--   select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'set_contrato_numero';
--
-- Los dos tienen que enseñar los mismos 13 tipos. Y `node contracts/listas.test.js`
-- comprueba que la app y el vocabulario también.
