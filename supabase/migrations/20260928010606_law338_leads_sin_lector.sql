-- LAW-338 — lw_lector deja de leer `leads`: permiso sin llamador.
-- erp-ok: B10 a la par (el maestro NO la necesita: allí `leads` es de un módulo apagado y authenticated conserva su
--   SELECT, así que erp_lector es copia legítima y quitárselo pondría en rojo el 7.v del canon).
-- Por qué (revisor-codigo, MEDIA, 28-sep-2026): lw_lector nació en L0 como copia de los SELECT de authenticated. LAW-385
--   (leads_cierra_insert_anon, 27/28-sep) quitó todo a anon y authenticated sobre `leads`, pero la copia del lector se
--   quedó. Ninguna función con dueño lw_lector nombra `leads` ni sus vistas (lead_tablero, lead_sugerencia): el CRM va por
--   crm_leads* / crm_leads_resumen, DEFINER de postgres. Un permiso sin llamador se quita («reducir la exposición»), no
--   se silencia en _CERRADAS_LAW338 (commit 005f6136, revertido en el siguiente).
-- Comprobación previa: si alguna función del lector nombra leads o sus vistas, no se aplica nada.
do $$
declare v_lista text;
begin
  select string_agg(p.proname, ', ') into v_lista from pg_proc p
   where pg_get_userbyid(p.proowner) = 'lw_lector'
     and p.prosrc ~ '\m(leads|lead_tablero|lead_sugerencia)\M';
  if v_lista is not null then raise exception 'leads: funciones de lw_lector que la leen: %', v_lista; end if;
end $$;

revoke select on public.leads from lw_lector;

do $$
begin
  if has_table_privilege('lw_lector', 'public.leads', 'select') or has_any_column_privilege('lw_lector', 'public.leads', 'select') then
    raise exception 'leads: lw_lector sigue leyéndola';
  end if;
end $$;
