-- Da de alta el permiso 'soporte' (herramienta nueva /intranet/soporte/,
-- catálogo en contracts/assets/herramientas.js) a quien ya tenía
-- 'compradores' en su ficha -- mismo criterio que el 18-ago-2026 cuando
-- Vencimientos se dio de alta a quien ya tenía Operaciones: sin esto, veinte
-- personas que ya trabajan con compradores se habrían quedado sin la
-- herramienta nueva en silencio.
--
-- destructivo-ok: no es destructivo -- solo APPEND de un permiso a un array
-- existente. No quita ninguna herramienta a nadie.
update public.usuarios
set herramientas = array_append(herramientas, 'soporte')
where 'compradores' = any(herramientas) and not ('soporte' = any(herramientas));

-- Comprobación: select count(*) from public.usuarios where 'soporte' = any(herramientas); -- 20 el 1-sep-2026
