/* Las diez herramientas de la suite pasan a vivir bajo `/intranet/` (26-ago-2026,
   decisión del owner: una herramienta interna no debe ocupar un nombre del
   espacio público — `/proyectos/` sonaba a página de marketing).

   Los triggers de notificación escriben la RUTA a la que lleva cada aviso, así
   que también hay que moverlas aquí: si no, la campana seguiría mandando a
   `/operaciones/?contrato=…` para siempre. Los avisos YA guardados conservan la
   ruta vieja y llegan igual, porque el `.htaccess` deja un 301 permanente.

   Se reescribe el TEXTO de cada función, no su lógica: lo único que cambia es el
   prefijo de la ruta. `prokind='f'` deja fuera agregados y procedimientos, sobre
   los que `pg_get_functiondef` ni siquiera se puede llamar. */
do $$
declare f record; nuevo text;
begin
  for f in
    select p.oid, p.proname, pg_get_functiondef(p.oid) as def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and pg_get_functiondef(p.oid) ~ '/(facturas|operaciones|compradores|proyectos|obra|documentacion|usuarios|vencimientos|creatividades|dossier)/'
  loop
    nuevo := regexp_replace(
      f.def,
      '(?<!intranet)/(facturas|operaciones|compradores|proyectos|obra|documentacion|usuarios|vencimientos|creatividades|dossier)/',
      '/intranet/\1/', 'g');
    if nuevo is distinct from f.def then
      execute nuevo;
      raise notice 'ruta actualizada en %', f.proname;
    end if;
  end loop;
end $$;;
