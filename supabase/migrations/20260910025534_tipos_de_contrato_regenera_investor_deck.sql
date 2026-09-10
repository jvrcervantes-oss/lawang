-- destructivo-ok: contiene DROP CONSTRAINT dentro de un bloque DO idempotente
-- (contracts/sql/tipos_de_contrato.sql, ya usado sin incidentes el 17-ago/7-sep/
-- 9-sep para anadir carta_reserva_pma y adenda por el mismo camino). Regenera el
-- CHECK y set_contrato_numero() desde la lista fuente unica tras anadir
-- carta_reserva_investor_deck -- no borra ninguna fila, comprueba primero que
-- ningun tipo existente se quede fuera.
-- destructivo-ok

do $$
declare
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
    ['cc00014_timon',          'CC', 'public.contratos_cc_seq'],
    ['carta_reserva_pma',      'CP', 'public.contratos_cp_seq'],
    ['adenda',                 'AD', 'public.contratos_ad_seq'],
    ['carta_reserva_investor_deck', 'CD', 'public.contratos_cd_seq']
  ];
  i          int;
  n          int := array_length(tipos, 1);
  huerfano   text;
  lista_sql  text := '';
  casos_sql  text := '';
  cuerpo     text;
begin
  select c.tipo into huerfano
    from public.contratos c
   where c.tipo is not null
     and not (c.tipo = any (array(select tipos[k][1] from generate_subscripts(tipos,1) k)))
   limit 1;
  if huerfano is not null then
    raise exception
      'El tipo "%" existe en filas de `contratos` y NO está en la lista de este fichero.', huerfano;
  end if;

  for i in 1..n loop
    execute format('create sequence if not exists %s', tipos[i][3]);
  end loop;

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

  execute 'create or replace function public.set_contrato_numero() returns trigger '
       || 'language plpgsql set search_path to '''' as $f$' || cuerpo || '$f$';

  raise notice 'tipos_de_contrato: % tipos · CHECK y set_contrato_numero() regenerados de la misma lista', n;
end $$;
;
