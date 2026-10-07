-- Reversion del paso 3A (Fase 2 empresas, 7-oct-2026): quita la puerta del propietario. La pantalla de Usuarios volveria a ofrecer solo los roles de siempre si se revierte tambien editores.js.
drop function if exists public.usuario_da_alcance(uuid, text, text[]);
