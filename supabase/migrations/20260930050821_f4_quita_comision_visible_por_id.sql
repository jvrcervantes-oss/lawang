-- destructivo-ok: función creada hoy en F4 sin llamador (revisor)
-- F4 · arreglo del revisor de código (30-sep-2026): fuera la forma por id de comision_visible.
-- Porqué: nació en 20260930041708 y ya en 042130 se le quitó EXECUTE a authenticated por no tener llamador. Medido el 30-sep
-- sobre pg_proc: ninguna función la llama (todas usan la forma de 4 argumentos), ni el front (grep en intranet/). Una pieza
-- sin llamador no se deja expuesta ni muerta (reducir la exposición, CLAUDE.md). No toca datos.
drop function if exists public.comision_visible(uuid);
