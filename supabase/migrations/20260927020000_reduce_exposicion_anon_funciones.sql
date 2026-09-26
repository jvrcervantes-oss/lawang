-- Reducir la exposición: anon deja de poder ejecutar 12 funciones que no necesita (LAW-344).
-- Máxima del owner (26-sep-2026): «si tenemos 200 endpoints y necesitamos 20, tengamos 20»
-- (contexto/seguridad_2026.md §1.ter). Decisión del owner (27-sep): hoy solo lo de anon.
--
-- CÓMO: el permiso NO lo tiene anon directamente, le llega por PUBLIC (`=X/postgres` en proacl,
-- comprobado el 27-sep). Un `revoke ... from anon` no hace nada y la migración habría dicho
-- «hecho» sin cambiar un permiso. Se quita a PUBLIC y se da EXPLÍCITO a `authenticated`, que así
-- queda exactamente igual que antes; postgres y service_role ya lo tienen explícito.
--
-- Por qué el impacto es cero, comprobado el 27-sep contra la base:
--   · anon no tiene SELECT en ninguna tabla de public y solo INSERT en `leads`; ninguno de los 7
--     triggers de abajo está en `leads` (bancos_perfiles, comisiones_devengadas,
--     condiciones_comision, contratos, cuentas_bancarias, documents, proveedores).
--   · Un trigger se dispara aunque el rol que escribe no tenga EXECUTE sobre su función (ese
--     permiso solo se mira al crear el trigger).
--   · Las 5 auxiliares las usan policies (con authenticated, que conserva el permiso) o funciones
--     SECURITY DEFINER (que corren como su dueño).
--
-- FUERA a propósito: `parcelas_tamanos_disponibles(text)`. La primera medición la daba por
-- sobrante porque ningún `rpc('...')` la nombraba, pero `/palmfield/vivo.php` la llama desde el
-- servidor con la clave publicable (rol anon): revocarla habría dejado la landing de los anuncios
-- sin la lista de tamaños. Tiene llamador con nombre; se queda.
--
-- Pendiente (LAW-344, segunda parte): las 31 funciones de trigger ejecutables por
-- `authenticated`, después de comprobar con el arnés (tools/flujos_lawang.py).

do $$
declare f text;
begin
  foreach f in array array[
    -- 7 funciones de trigger
    'public._bancos_perfil_autoria()',
    'public._cuenta_bancaria_blinda()',
    'public._documents_kyc_firmado()',
    'public._proveedores_autoria()',
    'public._trg_comision_devengo_guarda()',
    'public._trg_condicion_comision_manager()',
    'public.descuento_comercial_suelo_valido()',
    -- 5 auxiliares
    'public._sc_columnas_clients()',
    'public._sc_mes_cerrado(date)',
    'public._sc_visible(text, uuid)',
    'public.contrato_nombres_compradores(jsonb)',
    'public.traspaso_carta_estado(text, text[], text, text[])'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('revoke execute on function %s from anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
