-- Apoderada del Poder Notarial (serie PA) — 14-ago-2026, petición del owner.
--
-- El poder deja de otorgarse a I WAYAN EKA ARYAWAN y pasa a NI LUH GEDE DIAH
-- SURASTRI. I Wayan Eka NO se borra: sigue siendo el apoderado de la Primera
-- Parte en "4. Hak Sewa - Notario" (templates/hak_sewa_notario.html), que no se
-- toca. Quién aparece en cada documento lo decide OPCIONES_POR_PLANTILLA en
-- contracts/app.html, no esta tabla: el catálogo es común a los dos.
--
-- `clave` es el NOMBRE tal cual, porque es el valor del <select>
-- (hsn_apoderado_nombre en tokens.json) con el que app.html busca la fila —
-- ver cargarApoderadosHakSewa() en contracts/assets/entities.js. Si no coincide
-- carácter a carácter con la opción de tokens.json, el NIK no se autorrellena.
--
-- Solo NIK: el Poder Notarial imprime nombre + NIK y nada más. Edad, ocupación
-- y dirección son campos del Hak Sewa, que esta persona no firma — se dejan a
-- NULL en vez de inventarlas. `ktp` a NULL a propósito: el anexo con la
-- fotocopia del DNI se retiró del documento el mismo día por no tener el
-- escaneo (ver cabecera de templates/poa_notario.html).
--
-- Idempotente: se puede correr dos veces sin duplicar la fila.

insert into public.apoderados_hak_sewa (clave, nik, activo, orden)
select 'NI LUH GEDE DIAH SURASTRI', '5108014707010003', true, 2
where not exists (
  select 1 from public.apoderados_hak_sewa where clave = 'NI LUH GEDE DIAH SURASTRI'
);

-- Comprobación: deben salir las dos personas, activas.
-- select clave, nik, activo, orden from public.apoderados_hak_sewa order by orden;
