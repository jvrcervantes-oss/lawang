-- destructivo-ok: quita PERMISOS de escritura directa de la pantalla (revoke + drop de policies solo de escritura); no borra ni cambia ninguna fila ni ningún fichero. OK explícito del owner 26-sep-2026 (LAW-344) y permiso concedido para aplicarlo.
-- Frontera frontend/backend (LAW-336), cierre de las piezas 5, 6 y 7. Aplicada el 26/27-sep-2026 tras comprobar
-- que ninguna pantalla servida escribe ya directo en estas tablas ni buckets (grep de todo el repo: 0).
-- Verificado después: authenticated solo SELECT en las 12 tablas, 0 grants de escritura por columna, ninguna
-- policy de escritura de storage sobre contratos-firmados/justificantes; con sesión de agente, admin y manager
-- las escrituras directas fallan y las RPC (contrato_guarda, comision_marca_pagada, equipo_venta_activa) van.
-- Lectura: sin cambios (LAW-338).

-- Pieza 5: contratos, firmas, registro de correos y ficheros
drop policy if exists "agentes o su manager insertan contratos" on public.contratos;
drop policy if exists "el autor, su manager, o un admin editan contratos sin firma viv" on public.contratos;
drop policy if exists "borrar contratos" on public.contratos;
revoke insert, update, delete on public.contratos from authenticated;
drop policy if exists "agentes gestionan firmas (escritura)" on public.contrato_firmas;
drop policy if exists "agentes actualizan firmas" on public.contrato_firmas;
revoke insert, update, delete on public.contrato_firmas from authenticated;
drop policy if exists "agentes registran sus envios" on public.correos_enviados;
revoke insert, update, delete on public.correos_enviados from authenticated;
drop policy if exists "agentes autenticados suben pdf firmado" on storage.objects;
drop policy if exists "agentes reescriben el snapshot pendiente" on storage.objects;
drop policy if exists "agentes borran el snapshot pendiente" on storage.objects;
drop policy if exists "agentes reintentan su pdf manual sin bloquear" on storage.objects;
drop policy if exists "agentes suben justificantes" on storage.objects;

-- Pieza 6: comisiones (solo GRANT: varias policies FOR ALL dan también la lectura)
revoke insert, update, delete on public.condiciones_comision   from authenticated;
revoke insert, update, delete on public.condicion_tramos       from authenticated;
revoke insert, update, delete on public.comisiones_devengadas  from authenticated;
revoke insert, update, delete on public.comision_admin_tarifas from authenticated;
revoke insert, update, delete on public.comision_admin_fees    from authenticated;
revoke insert, update, delete on public.comision_admin_lineas  from authenticated;
revoke execute on function public.condicion_tramos_reemplaza(uuid, jsonb) from authenticated, public;

-- Pieza 7: usuarios y equipos (incluye el INSERT que dejaba a un admin crear un super_admin)
revoke insert, update, delete on public.usuarios        from authenticated;
revoke insert, update, delete on public.equipos_venta   from authenticated;
revoke insert, update, delete on public.equipo_miembros from authenticated;
