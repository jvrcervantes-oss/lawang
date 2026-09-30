-- AJUSTES DEL ERP · S5.0 F4 (AXW-124): las dos funciones SQL que mandan correo por pg_net (_avisar_equipo_soporte,
-- revisar_almacenamiento) pasan del PHP de Hostinger a la edge `envia-correo`. 30-sep-2026.
-- Solo cambia el valor del interruptor; las funciones ya lo leen (migración 20260930230000).
-- Probado antes: net.http_post con el mismo cuerpo que usan las funciones -> 200 {"ok":true} (net._http_response 912).
-- Vuelta atrás en un minuto: volver a poner 'https://lawangproperties.com/contracts/api/send_email.php'.
-- Ojo: sigue por la vía de aviso sin cabecera secreta (estrecha: solo texto a email_avisos_*); AXW-123 la cierra.
update public.config_instancia
   set valor = to_jsonb('https://vtulllundrfennhjddhc.supabase.co/functions/v1/envia-correo'::text)
 where clave = 'url_envio_correo';
