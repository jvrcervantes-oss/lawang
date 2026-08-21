-- Barrido de datos de clients.nationality/phone contra los desplegables
-- nuevos (prefijo E.164 + NACIONALIDADES = nombres de pais canonicos) de
-- compradores/index.html (11-ago-2026, peticion del owner). Confirmado con
-- el owner: normaliza SOLO las fichas reales -- se excluyen a proposito
-- "carmen"/"Juan"/"pablo"/"spwep" (aspecto de datos de prueba) y no se
-- fusiona el duplicado Ruben Carrasco / RUBEN CARRASCO BARJA (misma
-- normalizacion aplicada a las dos filas, la fusion queda para otra
-- decision). Cada fila va por su id -- no es un UPDATE masivo sin acotar.

update public.clients set nationality = 'España' where id = 'ba3fec67-d47b-4d6e-96b3-1b4a53332896'; -- Aranzazu Bahon Bueno: Española
update public.clients set nationality = 'España' where id = '5a62948d-b827-490c-ae38-9f8bc489539d'; -- Carlos Fragua Martinez: Española
update public.clients set nationality = 'España' where id = 'c515c80a-c299-4592-9be8-8b1adb2d89fe'; -- Cayetano Gimenez Lopez: Española
update public.clients set nationality = 'España' where id = 'eb5b3ab8-d318-427c-ad4e-a7e1367c240f'; -- David Aldeano Ruiz: Español
update public.clients set nationality = 'España' where id = '634ddc2b-b37f-4ad9-a74d-728703053cea'; -- David Bonet Rubio: Española
update public.clients set nationality = 'España' where id = '4568d2db-191d-4b86-9722-a75ffddb73d7'; -- Francisco García Cortés: Española
update public.clients set nationality = 'España' where id = '9072222f-3c40-4634-b374-7846e5cec687'; -- Francisco Sánchez: Española
update public.clients set nationality = 'España', phone = '+34601170044' where id = '0117a098-1419-4b26-bb00-b5ea01622dc6'; -- Javier Cervantes: Española / 601170044
update public.clients set nationality = 'España' where id = '1a10ed16-85a5-4cee-81ef-a80576d7f7ce'; -- Jesus Maria Diaz de Mera y Aranda: Spanish
update public.clients set nationality = 'España' where id = 'ef00fc35-edce-48ab-9054-1da7c914fbc1'; -- Joaquín Verdeguer García: Español
update public.clients set nationality = 'España' where id = 'aa31b42c-705f-46f4-891d-463b05d2cbe0'; -- Joel Fuguet Margeli: Española
update public.clients set nationality = 'España' where id = '01aa7ad0-ee77-47f7-afb2-72452be08973'; -- jose alacid perea: españa
update public.clients set nationality = 'España', phone = '+34 679 43 28 40' where id = '3938bdb1-6f64-4d57-aad0-47d6cc7c04e9'; -- Jose Pedro Oton Urbano: Sapnish / 34 679 43 28 40
update public.clients set nationality = 'España' where id = '2c713194-77e5-4140-9602-4ae5dcae116b'; -- Juan Carlos Giner Aliaga: Español
update public.clients set nationality = 'España', phone = '+34688980711' where id = 'd4c59acf-031b-4cbb-809c-b556047dddba'; -- Juan Ramón Sánchez García: Español / 688980711
update public.clients set nationality = 'España', phone = '+34688980711' where id = '2586da27-658b-43bc-9988-d6d0b8af32d4'; -- Mª Amparo Gómez Puchades: Española / 688980711
update public.clients set nationality = 'España' where id = 'a022d21d-4182-4d05-8bba-3a7d87c83a08'; -- María González Clemente: Española
update public.clients set nationality = 'Indonesia' where id = 'e4806570-69f8-40b0-b15d-95c31315ea42'; -- PT ROCHAS CREATIVE DESIGNS: INDONESIA
update public.clients set nationality = 'Rumania' where id = '799f68b2-ce32-4a64-b189-3ed9dadb4a01'; -- Radu Popovici: Romanian
update public.clients set nationality = 'España', phone = '+34 608 06 69 76' where id = 'f0391586-c524-4b72-9079-7760ee34c9e2'; -- Rubén Carrasco: Española / 608 06 69 76
update public.clients set nationality = 'España' where id = '53ffbd56-2d97-4cc9-b222-269956191373'; -- RUBÉN CARRASCO BARJA: ESPAÑOLA
update public.clients set nationality = 'España' where id = '2117cd19-be8a-473e-8827-b7abcdbb9fb0'; -- Silvia Adan Sevilla: Española
update public.clients set nationality = 'Países Bajos' where id = '8813ca92-83e1-4860-9bdd-b2969d199b0f'; -- Timon Taeke van den Bosch: Netherlands
update public.clients set nationality = 'España' where id = 'f3ae9301-d71d-402f-95d9-04a4c21dbe00'; -- Verónica Conejero González: Española
;
