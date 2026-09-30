-- F4 (30-sep-2026): dos funciones TRIGGER de comisiones_diferencias nacieron con EXECUTE para PUBLIC (default de
-- postgres), y eso las ponia en rojo en dos invariantes de tools/salud_lawang.py (anon sin grants; lw_lector lector).
-- Un trigger no necesita EXECUTE del que dispara la escritura: se quita a PUBLIC sin cambiar ningun comportamiento.
revoke execute on function public._trg_comision_diferencia_fija() from public;
revoke execute on function public._trg_comision_diferencia_no_borrar_viva() from public;
