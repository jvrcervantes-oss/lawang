do $mig$
declare d text;
begin
  select pg_get_functiondef(p.oid) into strict d
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
  where p.proname = 'portal_situacion';

  if position($m$'emisor',$m$ in d) > 0 then
    raise notice 'ya proyectaba emisor';
    return;
  end if;

  d := replace(d,
    $m$'fields',          f.datos->'fields'$m$,
    $m$'fields',          f.datos->'fields',
        'emisor',          f.datos->'emisor'$m$);

  execute d;
end $mig$;;
